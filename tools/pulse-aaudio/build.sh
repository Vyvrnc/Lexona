#!/bin/sh
# Builds module-aaudio-sink-lexona.so (Gitea #18) on the phone, in Lexona's Termux shell (clang from
# Termux). Needs the PulseAudio source of the installed version, headers only:
#   SRC=/path/to/pulseaudio-17.0/src sh tools/pulse-aaudio/build.sh
# config.h here is hand-written (no meson); PACKAGE_VERSION must be the daemon's own ("17.0-dirty"
# in Lexona), the module refuses to load otherwise. Output next to this script; it goes to
# app/android/app/src/main/assets/droiddesk/pulse/. First built on the Galaxy Z Fold 7, 2026-11-20.
set -eu
D=$(cd "$(dirname "$0")" && pwd)
P=${PREFIX:?run in the Termux shell of Lexona}
SRC=${SRC:?path to pulseaudio-VERSION/src}
B=$D/build
mkdir -p "$B/pulse"
cp "$D/config.h" "$B/config.h"
sed -e 's/@PA_MAJOR@/17/; s/@PA_MINOR@/0/; s/@PA_MICRO@/0/; s/@PA_API_VERSION@/12/; s/@PA_PROTOCOL_VERSION@/35/' \
    "$SRC/pulse/version.h.in" > "$B/pulse/version.h"
clang -shared -fPIC -O2 -DHAVE_CONFIG_H -DPA_MODULE_NAME=module_aaudio_sink_lexona \
    -I "$B" -I "$SRC" -I "$P/include" "$D/module-aaudio-sink.c" \
    -L "$P/lib/pulseaudio" -lpulsecore-17.0 -lpulsecommon-17.0 -lpulse -laaudio \
    -Wl,-soname,module-aaudio-sink-lexona.so -o "$D/module-aaudio-sink-lexona.so"
llvm-strip --strip-unneeded "$D/module-aaudio-sink-lexona.so"
sha256sum "$D/module-aaudio-sink-lexona.so"
