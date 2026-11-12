#!/bin/bash
# Read-only: what a DroidDesk install keeps in its homes, with sizes. Run in DroidDesk's terminal:
#   bash /sdcard/Download/lexona-migrate/inventory.sh
# Writes /sdcard/Download/lexona-migrate/inventory.txt.
set -u
out=/sdcard/Download/lexona-migrate/inventory.txt
R=$PREFIX/var/lib/proot-distro/containers/debian/rootfs
[ -d "$R" ] || R=$PREFIX/var/lib/proot-distro/installed-rootfs/debian
{
    echo "== app $PREFIX"
    echo "== Termux home $HOME"
    du -sh "$HOME"/.[!.]* "$HOME"/* 2>/dev/null | sort -h | tail -40
    echo "== Termux ~/.config"
    du -sh "$HOME"/.config/* 2>/dev/null | sort -h | tail -30
    echo "== Debian /root ($R/root)"
    du -sh "$R"/root/.[!.]* "$R"/root/* 2>/dev/null | sort -h | tail -40
    echo "== Debian /root/.config"
    du -sh "$R"/root/.config/* 2>/dev/null | sort -h | tail -30
    echo "== Debian /root/.local/share"
    du -sh "$R"/root/.local/share/* 2>/dev/null | sort -h | tail -20
    echo "== logins present"
    for f in "$R"/root/.claude/.credentials.json "$R"/root/.claude.json "$R"/root/.codex/auth.json \
             "$R"/root/.config/gh/hosts.yml "$HOME"/.config/gh/hosts.yml "$R"/root/.ssh "$HOME"/.ssh \
             "$R"/root/.gitconfig "$HOME"/.gitconfig "$HOME"/.mozilla "$R"/root/.mozilla; do
        [ -e "$f" ] && echo "yes $f" || echo "no  $f"
    done
    echo "== Debian manual packages"
    "$PREFIX"/bin/debian-run apt-mark showmanual 2>/dev/null | tr '\n' ' '; echo
    echo "== Termux manual packages"
    apt-mark showmanual 2>/dev/null | tr '\n' ' '; echo
    echo "== done $(date +%T)"
} > "$out" 2>&1
echo "inventory: $out"
