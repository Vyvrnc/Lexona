#!/bin/bash
# One-time move from DroidDesk Fold to Lexona, step 1 of 2. Run in DroidDesk's terminal:
#   LX_PASS=<one-time passphrase> bash /sdcard/Download/lexona-migrate/export.sh
# Packs the user data of Debian's /root and of the Termux home into one archive in shared storage,
# encrypted with LX_PASS (it holds SSH keys and Claude Code's history; other apps with storage
# access could read a plain file). Step 2: import.sh in Lexona's terminal, same LX_PASS.
# Not packed: Claude Code's binary (Lexona installs it), caches, files the app generates
# (desktop config, launchers, .bashrc/.profile) and gnome-keyring: its password comes from
# DroidDesk's Android Keystore key, so Lexona could not open it (sign in to Claude Code again).
set -euo pipefail
[ -n "${LX_PASS:-}" ] || { echo "Set LX_PASS: LX_PASS=... bash export.sh" >&2; exit 2; }
dir=/sdcard/Download/lexona-migrate
out=$dir/droiddesk-home.tar.gpg
FILES=$(dirname "$HOME")
R=$PREFIX/var/lib/proot-distro/containers/debian/rootfs
[ -d "$R" ] || R=$PREFIX/var/lib/proot-distro/installed-rootfs/debian
mkdir -p "$dir"

termux=()
for p in .ssh .gnupg .gitconfig .mozilla .config/gh .bash_history Desktop Documents Downloads Pictures Music Videos projekty; do
    [ -e "$HOME/$p" ] && termux+=("home/$p")
done
debian=()
[ -d "$R/root" ] && debian=(root)

args=(--exclude=root/.local/share/claude --exclude=root/.local/bin/claude --exclude=root/.local/share/keyrings
      --exclude=root/.cache --exclude=root/.npm --exclude=root/.config/droiddesk
      --exclude=root/.bashrc --exclude=root/.profile --exclude='*/node_modules'
      --exclude=root/.claude/shell-snapshots --exclude=root/.claude/statsig)
[ ${#debian[@]} -gt 0 ] && args+=(-C "$R" "${debian[@]}")
[ ${#termux[@]} -gt 0 ] && args+=(-C "$FILES" "${termux[@]}")
tar -cf - "${args[@]}" | gpg --batch --yes --quiet --no-symkey-cache --pinentry-mode loopback \
    --passphrase-file <(printf %s "$LX_PASS") --symmetric --cipher-algo AES256 -o "$out"
chmod 600 "$out" 2>/dev/null || true
echo "Packed: debian ${debian[*]:-none}; termux ${termux[*]:-none}"
ls -l "$out"
echo "Now in Lexona's terminal: LX_PASS=... bash $dir/import.sh"
