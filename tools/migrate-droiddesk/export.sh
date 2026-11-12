#!/bin/bash
# One-time move from DroidDesk Fold to Lexona, step 1 of 2. Run in DroidDesk's terminal and keep
# DroidDesk in the foreground until it ends (Android may kill a busy app in the background):
#   LX_PASS=<one-time passphrase> [LX_EXCLUDE="projekty apps .wine*"] [LX_SIZE=1] bash /sdcard/Download/lexona-migrate/export.sh
# Packs the user data of Debian's /root and of the Termux home into one archive in shared storage,
# encrypted with LX_PASS (it holds SSH keys and Claude Code's history; other apps with storage
# access could read a plain file). Step 2: import.sh in Lexona's terminal, same LX_PASS.
# Not packed: Claude Code's binary (Lexona installs it), caches, files the app generates
# (desktop config, launchers, .bashrc/.profile) and gnome-keyring: its password comes from
# DroidDesk's Android Keystore key, so Lexona could not open it (sign in to Claude Code again).
set -euo pipefail
[ -n "${LX_PASS:-}" ] || [ "${LX_SIZE:-0}" = 1 ] || { echo "Set LX_PASS: LX_PASS=... bash export.sh" >&2; exit 2; }
dir=/sdcard/Download/lexona-migrate
out=$dir/droiddesk-home.tar.gpg
FILES=$(dirname "$HOME")
R=$PREFIX/var/lib/proot-distro/containers/debian/rootfs
[ -d "$R" ] || R=$PREFIX/var/lib/proot-distro/installed-rootfs/debian
mkdir -p "$dir"

# Newer Firefox and git keep their files under ~/.config (XDG); autostart holds own entries
# such as the xset mouse speed.
termux=()
for p in ${LX_ONLY:-.ssh .gnupg .gitconfig .mozilla .config/mozilla .config/git .config/gh .config/autostart \
        .bash_history Desktop Documents Downloads Pictures Music Videos projekty}; do
    [ -e "$HOME/$p" ] && termux+=("home/$p")
done
debian=()
[ -d "$R/root" ] && debian=(root)
# LX_ONLY="paths": only these paths of the Termux home, into droiddesk-extra.tar.gpg (for things
# a first export missed; import with LX_IN=.../droiddesk-extra.tar.gpg).
if [ -n "${LX_ONLY:-}" ]; then
    debian=()
    out=$dir/droiddesk-extra.tar.gpg
    [ ${#termux[@]} -gt 0 ] || { echo "None of LX_ONLY exists in $HOME" >&2; exit 2; }
fi

# What the user installed and taught, as lists for import.sh: manually installed packages
# (Debian, Termux), glibc-native's learned proot fallbacks, own menu launchers (not the ones
# DroidDesk generates: debian-* from the menu sync, droiddesk-*).
meta=$(mktemp -d "$TMPDIR/lexona-meta.XXXXXX"); trap 'rm -rf "$meta"' EXIT
mkdir -p "$meta/meta/applications"
"$PREFIX/bin/debian-run" apt-mark showmanual > "$meta/meta/debian-manual.txt" 2>/dev/null || true
apt-mark showmanual > "$meta/meta/termux-manual.txt" 2>/dev/null || true
cp "$PREFIX/opt/glibc-native/proot-list" "$meta/meta/proot-list" 2>/dev/null || true
for f in "$HOME"/.local/share/applications/*.desktop; do
    [ -f "$f" ] || continue
    case ${f##*/} in debian-*|droiddesk-*) continue ;; esac
    cp "$f" "$meta/meta/applications/"
done
echo "Lists: $(wc -l < "$meta/meta/debian-manual.txt") Debian, $(wc -l < "$meta/meta/termux-manual.txt") Termux packages, $(ls "$meta/meta/applications" | wc -l) launchers"

args=(--exclude=root/.local/share/claude --exclude=root/.local/bin/claude --exclude=root/.local/share/keyrings
      --exclude=root/.cache --exclude=root/.npm --exclude=root/.config/droiddesk
      --exclude=root/.bashrc --exclude=root/.profile --exclude='*/node_modules'
      --exclude=root/.claude/shell-snapshots --exclude=root/.claude/statsig
      --exclude='home/.config/autostart/droiddesk-*' --exclude='home/.config/mozilla/firefox/*/cache2')
# LX_EXCLUDE: more paths to leave out, space separated, relative to Debian's /root or the Termux
# home, e.g. LX_EXCLUDE="projekty apps .wine* sd-a.img whisper mesa-build Downloads".
set -f  # the patterns go to tar as they are
for x in ${LX_EXCLUDE:-}; do
    args+=("--exclude=root/$x" "--exclude=home/$x")
done
set +f
[ ${#debian[@]} -gt 0 ] && args+=(-C "$R" "${debian[@]}")
[ ${#termux[@]} -gt 0 ] && args+=(-C "$FILES" "${termux[@]}")
args+=(-C "$meta" meta)
# LX_SIZE=1: only print how big the archive would be (nothing is written).
if [ "${LX_SIZE:-0}" = 1 ]; then
    echo "Archive size: $(( $(tar -cf - "${args[@]}" 2>/dev/null | wc -c) / 1048576 )) MB (before compression and encryption)"
    exit 0
fi
# nice: on the Fold 7 the first run (tar+gpg at full CPU) got DroidDesk killed in the background.
nice -n 19 tar -cf - "${args[@]}" | nice -n 19 gpg --batch --yes --quiet --no-symkey-cache --pinentry-mode loopback \
    --passphrase-file <(printf %s "$LX_PASS") --symmetric --cipher-algo AES256 -o "$out"
chmod 600 "$out" 2>/dev/null || true
echo "Packed: debian ${debian[*]:-none}; termux ${termux[*]:-none}"
ls -l "$out"
echo "Now in Lexona's terminal: LX_PASS=... LX_IN=$out bash $dir/import.sh"
