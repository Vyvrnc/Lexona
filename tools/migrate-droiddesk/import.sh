#!/bin/bash
# One-time move from DroidDesk Fold to Lexona, step 2 of 2. Run in Lexona's terminal (storage
# access granted) after export.sh in DroidDesk:
#   LX_PASS=<same passphrase> bash /sdcard/Download/lexona-migrate/import.sh
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

rm -f "$in"
echo "Done. The archive was deleted. Sign in to Claude Code again (claude-debian)."
