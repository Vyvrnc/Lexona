#!/usr/bin/env bash
# Builds the same Mesa as build.sh in Lexona's Debian on the phone (arm64, about 20 min with -j4
# on the Fold 7). Run it under proot: `DD_NATIVE=0 debian-run bash build-native.sh` (natively,
# meson install failed with OSError on the hard links of install_megadrivers.py). Needs the build
# dependencies from build.sh (apt, under proot).
# Usage: bash build-native.sh [PATCH_DIR]   PATCH_DIR holds our *.patch files (default: next to this script)
# Output: ~/mesa-kgsl-VERSION-REVISION-arm64.tar.xz and its sha256.
set -euo pipefail

# 26.3.1 (2026-11-20, Fold 7): glmark2-es2 1280x720 680 against 549 with 26.2.6. Termux's patch
# 0014 (wait_timestamp_safe) is gone from its 26.3 recipe; 0017 and 0018 stay.
MESA_VERSION=26.3.1
ASSET_REVISION=2
MESA_SHA256=4e4e438eac7b840a9383988cbb7c08dad8041da544b9319fc26d319fa7348961
TERMUX_PACKAGES_COMMIT=6c15200c8281bd911df95be359cd91a4542c8346
PATCH_DIR=${1:-$(cd "$(dirname "$0")" && pwd)}
WORK=${WORK:-$HOME/mesa-build}
JOBS=${JOBS:-4}

mkdir -p "$WORK" && cd "$WORK"
[ -f mesa-$MESA_VERSION.tar.xz ] || curl -fsSLo mesa-$MESA_VERSION.tar.xz https://archive.mesa3d.org/mesa-$MESA_VERSION.tar.xz
echo "$MESA_SHA256  mesa-$MESA_VERSION.tar.xz" | sha256sum -c -
rm -rf mesa-$MESA_VERSION stage
tar xf mesa-$MESA_VERSION.tar.xz
cd mesa-$MESA_VERSION
for p in 0017-preserve-egl-support-in-zink.patch \
         0018-disable-general-layout-in-zink-for-turnip.patch; do
    curl -fsSL https://raw.githubusercontent.com/termux/termux-packages/$TERMUX_PACKAGES_COMMIT/packages/mesa/$p | patch -p1
done
for p in "$PATCH_DIR"/*.patch; do patch -p1 < "$p"; done

meson setup build --prefix=/opt/mesa-kgsl --libdir=lib/aarch64-linux-gnu -Dbuildtype=release \
    -Dvulkan-drivers=freedreno -Dfreedreno-kmds=msm,kgsl -Dgallium-drivers=zink,softpipe -Dplatforms=x11 \
    -Dglx=dri -Degl=enabled -Dgbm=enabled -Dgles1=disabled -Dgles2=enabled -Dglvnd=enabled \
    -Dllvm=disabled -Dxmlconfig=disabled -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled \
    -Dvideo-codecs= -Dbuild-tests=false
ninja -C build -j"$JOBS"
DESTDIR="$WORK/stage" ninja -C build install
echo "$MESA_VERSION-$ASSET_REVISION" > "$WORK/stage/opt/mesa-kgsl/.droiddesk-version"
OUT=$HOME/mesa-kgsl-$MESA_VERSION-$ASSET_REVISION-arm64.tar.xz
tar -C "$WORK/stage" -cJf "$OUT" opt/mesa-kgsl
sha256sum "$OUT"
