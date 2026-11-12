#!/bin/bash
# One-time move from DroidDesk Fold to Lexona, step 2 of 2. Run in Lexona's terminal (storage
# access granted, the app in the foreground until it ends) after export.sh in DroidDesk:
#   LX_PASS=<same passphrase> bash /sdcard/Download/lexona-migrate/import.sh [--install] [--meta-only]
# --install    also reinstalls the packages installed by hand in DroidDesk (Termux and Debian).
# --meta-only  everything except unpacking the homes again: path rewrites, symlinks, launchers,
#              proot-list, package lists (and --install); after a run that stopped half way.
# LX_IN=<file> another archive, e.g. droiddesk-extra.tar.gpg from export.sh with LX_ONLY.
# Unpacks into Lexona's Debian /root and Termux home. Anything already there with the same name
# is kept as NAME.pre-migrate-<time>, nothing is deleted. Paths of the old app
# (com.orailnoor.droiddesk) in Claude Code's config and history, in text configs and in symlinks
# (proot's hard-link emulation, .l2s) are rewritten to Lexona's.
# The encrypted archive is kept; delete it by hand once everything checks out.
# Quit Claude Code first: its config (/root/.claude, /root/.claude.json) is merged too, and a
# running Claude Code would overwrite the merged .claude.json with its own copy.
set -euo pipefail
install=0 metaonly=0
for a in "$@"; do
    case $a in
        --install) install=1 ;;
        --meta-only) metaonly=1 ;;
        *) echo "Unknown option: $a" >&2; exit 2 ;;
    esac
done
[ -n "${LX_PASS:-}" ] || { echo "Set LX_PASS: LX_PASS=... bash import.sh" >&2; exit 2; }
if { pgrep -x claude >/dev/null 2>&1 || pgrep -f '\.local/(share|bin)/claude' >/dev/null 2>&1; }; then
    echo "Claude Code is running; quit it (all sessions) and run import.sh again." >&2; exit 3
fi
dir=/sdcard/Download/lexona-migrate
in=${LX_IN:-$dir/droiddesk-home.tar.gpg}
[ -f "$in" ] || { echo "Missing $in (run export.sh in DroidDesk first)" >&2; exit 2; }
R=$PREFIX/var/lib/proot-distro/containers/debian/rootfs
[ -d "$R" ] || R=$PREFIX/var/lib/proot-distro/installed-rootfs/debian
stamp=$(date +%Y%m%d-%H%M%S)
work=$(mktemp -d "$TMPDIR/lexona-import.XXXXXX")
trap 'rm -rf "$work"' EXIT
old=com.orailnoor.droiddesk new=io.github.vyvrnc.lexona
olddash=com-orailnoor-droiddesk newdash=io-github-vyvrnc-lexona

only=()
[ $metaonly = 1 ] && only=(meta)
nice -n 19 gpg --batch --quiet --no-symkey-cache --pinentry-mode loopback --passphrase-file <(printf %s "$LX_PASS") \
    -d "$in" | nice -n 19 tar -xf - -C "$work" "${only[@]}"

place() {  # place SRC_DIR DEST_DIR: imported entries win; Lexona's own files stay
    local src=$1 dest=$2 e name
    [ -d "$src" ] || return 0
    mkdir -p "$dest"
    for e in "$src"/.[!.]* "$src"/*; do
        [ -e "$e" ] || [ -L "$e" ] || continue
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

relink() {  # relink DIR: symlinks into the old app's data dir point into Lexona's
    local l t n
    find "$1" -type l -lname "*$old*" 2>/dev/null | while read -r l; do
        t=$(readlink "$l")
        case $t in
            */containers/debian/rootfs/*) n=$R/${t#*/containers/debian/rootfs/} ;;
            */installed-rootfs/debian/*) n=$R/${t#*/installed-rootfs/debian/} ;;
            *) n=${t//$old/$new} ;;
        esac
        ln -sfn "$n" "$l" && echo "link: $l -> $n"
        [ -e "$n" ] || echo "  (target missing)"
    done
    return 0
}

if [ $metaonly = 0 ]; then
    place "$work/root" "$R/root"
    place "$work/home" "$HOME"
fi

# Old app paths -> Lexona's (Claude Code keys projects and history by path).
[ -f "$R/root/.claude.json" ] && sed -i "s#$old#$new#g" "$R/root/.claude.json"
if [ -d "$R/root/.claude/projects" ]; then
    for p in "$R"/root/.claude/projects/*"$olddash"*; do
        [ -e "$p" ] || continue
        target=${p//$olddash/$newdash}
        if [ -e "$target" ]; then echo "history kept under the old name: $p"; else mv "$p" "$target"; fi
    done
fi
for s in "$HOME/.ssh" "$R/root/.ssh"; do
    [ -d "$s" ] || continue
    chmod 700 "$s"; chmod 600 "$s"/id_* 2>/dev/null || true
done

# Old app paths in text configs (Claude Code settings and hooks, ~/.config, own scripts); the
# conversation history itself is left as written. grep finds nothing = exit 1, hence || true.
for d in "$R/root/.claude" "$R/root/.config" "$R/root/.local/bin" "$HOME/.config/autostart" "$HOME/.config/git"; do
    [ -d "$d" ] || continue
    { grep -rlI --exclude-dir=projects --exclude-dir=todos "$old" "$d" 2>/dev/null || true; } | while read -r f; do
        sed -i "s#$old#$new#g" "$f" && echo "paths rewritten: $f"
    done
done
relink "$R/root"
relink "$HOME"

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
    if [ $install = 1 ]; then
        missing() { comm -23 <(sort -u "$1") <(eval "$2" 2>/dev/null | sort -u) || true; }
        install_each() {  # install_each "CMD" LIST: one batch, then one by one on failure
            local cmd=$1 list=$2 p failed=()
            [ -s "$list" ] || return 0
            # shellcheck disable=SC2046
            $cmd $(cat "$list") >/dev/null 2>&1 && { echo "installed: $(wc -l < "$list")"; return 0; }
            while read -r p; do $cmd "$p" >/dev/null 2>&1 || failed+=("$p"); done < "$list"
            [ ${#failed[@]} -eq 0 ] || echo "not installed (not in the repositories? reinstall by hand): ${failed[*]}"
            return 0
        }
        if [ -f "$meta/termux-manual.txt" ]; then
            missing "$meta/termux-manual.txt" "apt-mark showmanual" > "$keep/termux-missing.txt"
            echo "Termux packages to install: $(wc -l < "$keep/termux-missing.txt")"
            install_each "pkg install -y" "$keep/termux-missing.txt"
        fi
        if [ -f "$meta/debian-manual.txt" ]; then
            missing "$meta/debian-manual.txt" "debian-run apt-mark showmanual" > "$keep/debian-missing.txt"
            echo "Debian packages to install: $(wc -l < "$keep/debian-missing.txt")"
            install_each "debian-run apt-get install -y -q" "$keep/debian-missing.txt"
        fi
    else
        echo "Package lists in $keep (reinstall: rerun with --meta-only --install)"
    fi
fi

echo "Done. The archive is kept: $in"
echo "Delete it yourself once everything checks out (it holds SSH keys). Sign in to Claude Code again if it asks (claude-debian)."
