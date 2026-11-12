#!/usr/bin/env bash
# targetSdk >= 29: glibc-native's loader has to be executable, and Android executes only files in
# the APK's nativeLibraryDir. Builds, from Debian trixie's libc6 (arm64):
#   jniLibs/arm64-v8a/libld.so                    patched ld-linux-aarch64.so.1 ($PLIB/ld.so links to it)
#   assets/droiddesk/glibc-native/glibc/libc.so.6 patched libc, same build as the loader
#   assets/droiddesk/glibc-native/glibc/*.so*     the rest of libc6 (libm, libresolv, nss, ...)
#   assets/droiddesk/glibc-native/glibc/VERSION   the libc6 version (also record it in COMPLIANCE.md)
# ld.so and libc share GLIBC_PRIVATE internals, so glibc-native puts the whole set first in
# its library path. Run from the repo root; needs Docker with arm64 emulation. Commit the outputs.
set -euo pipefail
to_host() { command -v cygpath >/dev/null && cygpath -m "$1" || echo "$1"; }
REPO=$(to_host "$PWD")

MSYS_NO_PATHCONV=1 docker run --rm --platform linux/arm64 -v "$REPO:/repo" debian:trixie bash -c '
set -euo pipefail
apt-get update -qq >/dev/null
apt-get install -y -qq python3 >/dev/null 2>&1
app=/repo/app/android/app/src/main
p=$app/assets/droiddesk/glibc-native/patch-glibc.py
out=$app/assets/droiddesk/glibc-native/glibc
rm -rf "$out"; mkdir -p "$out"
L=/usr/lib/aarch64-linux-gnu
python3 "$p" ld "$L/ld-linux-aarch64.so.1" "$app/jniLibs/arm64-v8a/libld.so"
python3 "$p" libc "$L/libc.so.6" "$out/libc.so.6"
for f in $(dpkg -L libc6 | grep -E "^/usr/lib/aarch64-linux-gnu/[^/]+\.so(\.[0-9]+)*$"); do
    b=${f##*/}
    case $b in ld-linux-aarch64.so.1|libc.so.6) continue ;; esac
    [ -L "$f" ] && continue
    cp "$f" "$out/$b"
done
dpkg-query -W -f "\${Version}\n" libc6 > "$out/VERSION"
chmod 644 "$out"/* "$app/jniLibs/arm64-v8a/libld.so"
echo "libc6 $(cat "$out/VERSION")"; ls -l "$out" "$app/jniLibs/arm64-v8a/libld.so"
'
