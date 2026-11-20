# module-aaudio-sink with the real latency

Termux's PulseAudio sends sound to Android through `module-aaudio-sink`
(termux-packages, `packages/pulseaudio/module-aaudio-sink.c`). The stock module sets only a
fixed latency and answers `PA_SINK_MESSAGE_GET_LATENCY` with 0, so clients do no A/V sync:
Chromium played Netflix's sound over Bluetooth A2DP audibly behind the picture (Galaxy Z Fold 7,
2026-11-20, Gitea #18).

`0001-aaudio-sink-report-latency.patch` answers `GET_LATENCY` with the frames AAudio has taken
but not presented yet: `AAudioStream_getFramesWritten` minus the presentation position from
`AAudioStream_getTimestamp` (extrapolated to now; it includes the HAL and, on current Android,
A2DP). Without a timestamp it falls back to written minus read. `module-aaudio-sink.c` is the
patched file.

## Build (on the phone, Termux side of Lexona)

Pulse modules are built against the PulseAudio source of the installed version (Termux does not
ship the `pulsecore` headers):

1. `pulseaudio --version` and the matching tarball from https://freedesktop.org/software/pulseaudio/releases/
2. In the source tree a configured build for `config.h` (`meson setup build` with the options
   Termux's `packages/pulseaudio/build.sh` uses), then replace `src/modules/module-aaudio-sink.c`
   with the patched file.
3. Only the module:
   ```
   clang -shared -fPIC -O2 -DHAVE_CONFIG_H -DPA_MODULE_NAME=module_aaudio_sink \
     -I build -I src -I "$PREFIX/include" src/modules/module-aaudio-sink.c \
     -L "$PREFIX/lib/pulseaudio" -lpulsecore-<version> -lpulsecommon-<version> -lpulse -laaudio \
     -Wl,-rpath,"$PREFIX/lib/pulseaudio" -o module-aaudio-sink.so
   ```

## Test

`pactl load-module <path>/module-aaudio-sink.so latency=60 sink_name=AAudio_fixed`, make it the
default sink, move Chromium's sink input there. `pactl list sinks` must show a non-zero
`Latency`; Chromium's video then waits for the sound.
