#!/bin/bash
# One-time move from DroidDesk Fold to Lexona, step 2 of 2. Run in Lexona's terminal (storage
# access granted) after export.sh in DroidDesk:
#   LX_PASS=<same passphrase> bash /sdcard/Download/lexona-migrate/import.sh [--install]
# --install also reinstalls the packages installed by hand in DroidDesk (Termux and Debian).
# Unpacks into Lexona's Debian /root and Termux home. Anything already there with the same name
# is kept as NAME.pre-migrate-<time>, nothing is deleted. Paths of the old app
# (com.orailnoor.droiddesk) in Claude Code's config and history are rewritten to Lexona's.
# The encrypted archive is deleted at the end.
set -euo pipefail
[ -n "${LX_PASS:-}" ] || { echo "Set LX_PASS: LX_PASS=... bash import.sh" >&2; exit 2; }
dir=/sdcard/Download/lexona-migrate
in=$dir/droiddesk-home.tar.gpg
[ -f "$in" ] || { echo "Missing $in (run export.sh in DroidDesk first)" >&2; exit 2; }
FILES=$(dirname "$HOME")
R=$PREFIX/var/lib/proot-distro/containers/debian/rootfs
[ -d "$R" ] || R=$PREFIX/var/lib/proot-distro/installed-rootfs/debian
stamp=$(date +%Y%m%d-%H%M%S)
work=$(mktemp -d "$TMPDIR/lexona-import.XXXXXX")
trap 'rm -rf "$work"' EXIT

gpg --batch --quiet --no-symkey-cache --pinentry-mode loopback --passphrase-file <(printf %s "$LX_PASS") \
    -d "$in" | tar -xf - -C "$work"

place() {  # place SRC_DIR DEST_DIR: imported entries win; Lexona's own files stay
    local src=$1 dest=$2 e name
    [ -d "$src" ] || return 0
    mkdir -p "$dest"
    for e in "$src"/.[!.]* "$src"/*; do
        [ -e "$e" ] || continue
        name=${e##*/}
        if [ -e "$dest/$name" ] || [ -L "$dest/$name" ]; then
            # A copy of the old state as NAME.pre-migrate-TIME; directories are merged, so
            # files only Lexona has (its keyring, Claude Code's binary) stay in place.
            cp -a "$dest/$name" "$dest/$name.pre-migrate-$stamp"
            echo "kept aside: $dest/$name.pre-migrate-$stamp"
            if [ -d "$e" ] && [ -d "$dest/$name" ] && [ ! -L "$dest/$name" ]; then
                cp -a "$e/." "$dest/$name/"
                echo "merged: $dest/$name"
                continue
            fi
            rm -rf "$dest/$name"
        fi
        mv "$e" "$dest/$name"
        echo "imported: $dest/$name"
    done
}
place "$work/root" "$R/root"
place "$work/home" "$HOME"

# Old app paths -> Lexona's (Claude Code keys projects and history by path).
old=com.orailnoor.droiddesk new=io.github.vyvrnc.lexona
olddash=com-orailnoor-droiddesk newdash=io-github-vyvrnc-lexona
[ -f "$R/root/.claude.json" ] && sed -i "s#$old#$new#g" "$R/root/.claude.json"
if [ -d "$R/root/.claude/projects" ]; then
    for p in "$R"/root/.claude/projects/*"$olddash"*; do
        [ -e "$p" ] || continue
        target=${p//$olddash/$newdash}
        if [ -e "$target" ]; then echo "history kept under the old name: $p"; else mv "$p" "$target"; fi
    done
fi
[ -d "$HOME/.ssh" ] && chmod 700 "$HOME/.ssh" && chmod 600 "$HOME"/.ssh/id_* 2>/dev/null || true

# Old app paths in text configs (Claude Code settings and hooks, ~/.config, own scripts); the
# conversation history itself is left as written.
for d in "$R/root/.claude" "$R/root/.config" "$R/root/.local/bin"; do
    [ -d "$d" ] || continue
    grep -rlI --exclude-dir=projects --exclude-dir=todos "$old" "$d" 2>/dev/null | while read -r f; do
        sed -i "s#$old#$new#g" "$f" && echo "paths rewritten: $f"
    done
done

meta=$work/meta
if [ -d "$meta" ]; then
    # Own menu launchers, with Lexona's paths; an existing one of the same name stays.
    mkdir -p "$HOME/.local/share/applications"
    for f in "$meta"/applications/*.desktop; do
        [ -f "$f" ] || continue
        t=$HOME/.local/share/applications/${f##*/}
        if [ -e "$t" ]; then echo "launcher kept (exists): $t"; continue; fi
        sed "s#$old#$new#g" "$f" > "$t" && echo "launcher: $t"
    done
    # Programs glibc-native learned to run under proot.
    if [ -s "$meta/proot-list" ]; then
        pl=$PREFIX/opt/glibc-native/proot-list; mkdir -p "${pl%/*}"; touch "$pl"
        sort -u "$pl" "$meta/proot-list" -o "$pl" && echo "proot-list: $(wc -l < "$pl") programs"
    fi
    # Package lists for later reinstalls, and the reinstall itself with --install.
    keep=$HOME/lexona-migrate; mkdir -p "$keep"
    cp "$meta"/*-manual.txt "$keep/" 2>/dev/null || true
    if [ "${1:-}" = --install ]; then
        missing() { comm -23 <(sort -u "$1") <(sort -u <(eval "$2")); }
        install_each() {  # install_each "CMD" LIST: one batch, then one by one on failure
            local cmd=$1 list=$2 p failed=()
            [ -s "$list" ] || return 0
            # shellcheck disable=SC2046
            $cmd $(cat "$list") >/dev/null 2>&1 && { echo "installed: $(wc -l < "$list")"; return 0; }
            while read -r p; do $cmd "$p" >/dev/null 2>&1 || failed+=("$p"); done < "$list"
            [ ${#failed[@]} -eq 0 ] || echo "not installed (not in the repositories? reinstall by hand): ${failed[*]}"
        }
        missing "$meta/termux-manual.txt" "apt-mark showmanual" > "$keep/termux-missing.txt"
        echo "Termux packages to install: $(wc -l < "$keep/termux-missing.txt")"
        install_each "pkg install -y" "$keep/termux-missing.txt"
        missing "$meta/debian-manual.txt" "debian-run apt-mark showmanual" > "$keep/debian-missing.txt"
        echo "Debian packages to install: $(wc -l < "$keep/debian-missing.txt")"
        install_each "debian-run apt-get install -y -q" "$keep/debian-missing.txt"
    else
        echo "Package lists in $keep (reinstall: rerun with --install after a new export, or by hand)"
    fi
fi

rm -f "$in"
echo "Done. The archive was deleted. Sign in to Claude Code again (claude-debian)."
