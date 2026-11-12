# Release verification

What each release was checked on, how, and what was **not** checked. Every APK is signed with
the same certificate; Android refuses an update signed with any other one.

Signing certificate SHA-256: `bb99b57e2d04953588f646c9a2d4d84e98b693f22ab795a70ccd4b773b13e72d`
(`apksigner verify --print-certs DroidDesk-fold-dex.apk`).

Devices:

- **Tab S10 FE**: Samsung Galaxy Tab S10 FE (SM-X620), Exynos 1580 / Xclipse 540, Android 16.
- **Fold 7**: Samsung Galaxy Z Fold 7 (SM-F966B), Snapdragon 8 Elite / Adreno 830, Android 17 (Android 16, One UI 8.5 before fold.106).

- **Galaxy A16**: Samsung Galaxy A16 (SM-A165F), MediaTek Helio G99 (MT6789) / Mali-G57 MC2, 4 GB, Android 16. Low-end test phone.

Unless stated otherwise, every release is installed over the previous one (`adb install -r`,
same as an Obtainium update) and the existing Debian, settings and Claude Code login are kept.

Automated checks before every release: `tools/glibc-native/test.sh` (pathhook and launcher
regressions in a Debian container) and `tools/check-launchers.py` (`bash -n` over the generated
launchers).

## Lexona 2.0.5 candidate on the Galaxy A16 (2026-11-12)

Process limit screen, tested with the limit on (Android's default) and restored afterwards:
- Shows the state and the Linux programs (23 with the desktop). Developer options open from
  the button; Samsung's switch ("Vypnout omezení podřízených procesů") set the override to
  false and the screen showed "off" on return.
- lexona-unlimit from Lexona's terminal with Settings in a pop-up window: paired over Wireless
  debugging, set monitor=false / max_phantom_processes=2147483647 and verified; a second run
  (--undo) connected with the port only (no new pairing) and restored null/null. Termux's adb
  has no mDNS, so the port is typed.
- Lean desktop, all six parts off: 12 Linux programs instead of 23; desktop up, no Trash icon,
  no USB icon. Back on: 23 again. Found and fixed on the way: pkill -f ended the desktop's
  own start script (bracketed patterns now), gvfsd came up over D-Bus (blocked now), inverted
  switches, the screen unreachable with the limit off, the unlimit window restarting itself.
- Not tested on a device: Android -> Linux clipboard (901dd70).

## Open for 2.0.5 (found on the Fold 7, 2026-11-12)

- **Android -> Linux clipboard**: worked in older DroidDesk Fold (xclip poller), not in Lexona.
  Candidate fix 901dd70 (any text clip, coerceToText); not yet tested on a device.
- **apt hangs in a Claude Code session started from Lexona**: the session runs under proot
  (TracerPid = linker64 .../proot, via droiddesk-tmux-host -> debian-run); a child apt forks
  stays in `t` (ptrace_stop), a nested debian-run times out, and `exec /system/bin/sh` from
  the Termux environment under that tracer fails with EPERM (bad interpreter).
- **Termux postinsts that set `LD_PRELOAD=''`** (lv2: `pip3 install pygments rdflib`) drop the
  socket hook: no network, no exec from the data dir at targetSdk 36; lv2, lilv, sratom,
  pipewire and chromium stayed unconfigured. Workaround: install the pip packages first.
- **Captured mouse slow outside DeX**: diagnosis with the MouseDiag log still pending.
- Phantom processes: list the desktop's processes on the Fold (27) and trim (at-spi, gvfs,
  tumbler, wrapper scripts without exec); check Android's developer option
  "Disable child process restrictions".

## Lexona 2.0.4 (2026-11-12)

Released without a whole-build device test (the A16 was offline). Stop server with feedback
and a kill of leftovers, Chromium in the catalog (execve of /proc/self/exe), the Claude symbol
for Claude Code, phantom-limit warning, migration scripts. The migration from DroidDesk Fold
was then run on the Fold 7 with Lexona 2.0.4 installed: homes, launchers and proot-list moved;
the import script needed fixes (2b7ae11, 4799c38, a4a955b).

## Lexona 2.0.3 (2026-11-12)

Released without a whole-build device test (the A16 was offline); adds an opt-in
captured-mouse log ($TMPDIR/lexona-mouse-diag -> $TMPDIR/lexona-mouse.log).

- pathhook maps `__xstat`/`__lxstat`/`__fxstatat` (glibc < 2.33 ABI): RustDesk 1.5.3 (Flutter)
  showed no text natively. Verified on the Fold 7 in DroidDesk with the new pathhook.so
  (bc1a21c): text, ID and the session list render natively; the Claude session there kept
  running on it. Regression checks in tools/glibc-native/test.c.
- Captured mouse: default speed 200 % on DeX/monitors, 150 % elsewhere (was 100 %, slow
  without Android's acceleration), a 400 % step, and the hint names the button (hold „Myš“).
  Not yet tested on a device.

## Lexona 2.0.2 (2026-11-12)

Full functional test on the Galaxy A16 (`tools/device-test/full.sh --heavy` in the app's terminal
and `tools/device-test/lifecycle.sh` over adb; build cb35254, the release adds only text): 44 PASS,
1 LIMIT, 1 SKIP.
- Exec: bash identity, `#!/usr/bin/env` scripts (new), Python subprocess and fork+execv,
  `/proc/self/exe`, pipes/xargs/find -exec, static programs in app data through proot (new),
  Go programs starting children through proot (new: `gh` alias 0.4 s). 200 execs of app-data
  programs (linker64) 4.9 s against 5.1 s for /system/bin: no overhead from the system linker.
- Termux: pkg install, git clone over HTTPS, ssh-keygen, pip, clang compiling and running a C
  program in `$HOME`.
- Debian: native glibc, glibc to Termux programs, proot route, apt install (hello, python3,
  mesa-utils), Debian python3 natively, Debian OpenGL with `lexona-gpu on` (virgl on the Mali).
- Desktop: XFCE processes, xfce4-terminal, Thunar, Mousepad, Ristretto windows, screenshot, X
  clipboard both ways (Android to X when the desktop comes to the front), Firefox headless page.
- Android: shared storage, audio playback, network bridge, DNS/HTTPS, USB, serial and camera
  bridges reachable on the new lexona.* sockets, droiddesk-eth from the APK.
- Lifecycle: app in the background 120 s, rotation, session notification, force-stop leaves no
  Linux process behind, launcher bridge listening, no droiddesk.* sockets (runs next to
  DroidDesk). Screen off 60 s kept the session too, but locked the PIN-protected phone, so the
  start after force-stop was not checked.
- Linux processes of the desktop: 23 (was 25: no gpg-agent, no Thunar daemon). With Android's
  limit on, a clang + apt run killed xfce4-session, PulseAudio and the Debian bus after 5 min;
  the full run was done with the limit off and the setting restored afterwards.
- LIMIT (same at targetSdk 28): a program started with `env -i` loses the hook and
  LD_LIBRARY_PATH, so it cannot start further Termux programs.
- SKIP: Claude Code on the clean install (its installer is the user's to run).

Not tested: USB devices (none at hand), Chromium, Electron mirrors, Wine/Box64, camera with the
permission granted, microphone, DeX/mouse right button, Fold 7, Tab S10 FE.

## Lexona 2.0.1 (2026-11-12)

Tested on Galaxy A16 (adb, by hand on the screen):
- Update from 2.0.0 over a running desktop: desktop back in 15 s, new wallpaper (mascot at the
  bottom centre, visible in portrait), desktop controls scroll sideways and "Myš"/"−" stay in
  reach. Smoke test (tools run in the in-app terminal) 18/18: bash identity, no setlocale
  warnings, lexona-* commands, pkg, python, glibc-native (debian-run native, glibc to Termux,
  apt through proot), Claude Code natively, Firefox, X, virgl on the Mali, XFCE processes,
  PulseAudio, D-Bus, network bridge, internet.
- Clean install (app data cleared): welcome screen with the new subtitle; notifications, then
  microphone, then the All files access page; setup about 20 min; "Launch Lexona" fully on
  screen; home screen warns about the child process limit, its dialog opens; first desktop in
  17 s. Smoke test 13/13 of what a clean install has (Claude Code, Firefox, glxinfo and the
  virgl opt-in are not part of it). Then `pkg install firefox mesa-demos` (one transient
  "index files failed to download" from the mirror, fine on retry), `lexona-native-gpu on`,
  Stop desktop (XFCE gone, terminal stays), Launch again (13 s, virgl server up): smoke test
  17/17 without Claude Code; GPU kit: virgl on Mali-G57, Mesa 26.2.7, glxgears 118 FPS,
  Firefox WebGL 2 ok at 32 FPS.

Not tested: Tab S10 FE and Fold 7 (not at hand).

## Lexona 2.0.0 (2026-11-12)

First release as Lexona: new app ID `io.github.vyvrnc.lexona` (installs next to DroidDesk,
nothing is migrated yet), targetSdk 36. The release build is the last test build without the
debug-only SmokeInstrumentation.

Tested on Galaxy A16 and Tab S10 FE (adb, clean install, by hand on the screen):
- Full in-app setup (A16 ~16 min), XFCE desktop (A16 8-14 s to xfdesktop), xfce4-terminal,
  in-app terminal with extra keys above the keyboard, `pkg install`, proot-distro Debian,
  `debian-run` (0.98 s on the A16).
- A16 with the desktop running: ~730 MB RSS for all Lexona processes (app UI 268 MB, X 80 MB,
  xfce4-session 61 MB, USB tray 58 MB); idle CPU about 5 % of one core (X).
- GPU kit, A16: llvmpipe glxgears 195-222 FPS; virgl (`droiddesk-native-gpu on`) on
  Mali-G57 MC2 works, glxgears 142 FPS; glmark2 960x540: score 41 software vs 47 virgl,
  refract 4 vs 33 FPS, desktop blur 11 vs 37, jellyfish 21 vs 43, texture 106 vs 45.
- GPU kit, Tab S10 FE: llvmpipe, Mesa 26.2.6, glxgears ~350 FPS.

- Firefox 159 (Termux) on the A16 with virgl: WebGL 2 about 34 FPS on the GPU kit test page,
  after the socket hook resolves symlinks in /proc/self/exe (before: "Couldn't load XPCOM").

- glibc-native at targetSdk 36 (A16): the APK's libld.so and glibc 2.41-12+deb13u4; Debian
  programs natively, glibc to Termux programs, apt through proot; `debian-run true` 0.33 s
  (0.98 s through proot).
- Phantom processes (A16, limit on): with 37 processes Android killed the two oldest after
  5 minutes; the home screen warns about the limit.

- Claude Code 2.1.322 natively at targetSdk 36 (A16, installed from the app catalog): `claude
  --version` 0.5 s, its embedded ripgrep through the argv0 "rg" re-exec finds files.

- Tab S10 FE: a gpg-agent left from an earlier session kept XFCE black; the session script now
  kills one that does not answer, the desktop then started in 4 s. The wallpaper mascot stays
  visible on 16:10.

Not tested: the 2.0.0 release APK itself beyond install and desktop start (see below); Electron
mirrors natively at targetSdk 36; Chromium and Debian OpenGL on Mali; Fold 7; a mouse's right button (BACK).

## 1.0.1-fold.108 (2026-11-02)

Fixed: a setup interrupted inside apt could not recover. On the ScreenMate One (Adreno 610,
Android Automotive 14) an OTA reboot killed the first setup of fold.107; afterwards every
install failed with "Unable to parse package file .../extended_states" and each retry stopped
at x11-repo/tur-repo. Before the first install step the setup now runs `dpkg --configure -a`
and, when `apt-get check` names extended_states, moves the file aside
(`extended_states.broken-<time>`; it only holds the auto-installed flags).

Tested: the repair script on a deliberately corrupted extended_states in a Debian trixie
container (apt-get check fails, file moved aside, apt-get check passes); `check-launchers`.
Not tested on the ScreenMate (no adb root since its OTA; needs a person at the device).

Also: `droiddesk-net` explains EPERM (found on the Fold 7 with Tailscale as the default network:
Android forbids binding to eth0 while a VPN without bypass covers the app) and `status` warns
when the default network is a VPN. Tested: the hint text from the module (py_compile); not on a
device.

Also: the USB panel icon was cut to its corner again after switching to DeX (Fold 7,
2026-11-11): GDK in the running tray kept scale 2 while xsettings said 1, so the reload by GDK's
scale did nothing. The tray now compares GDK's scale with xsettings every 10 s and starts
itself again while idle (no tray operation, no window open), once per scale. Tested: py_compile
only; the switch test on the Fold follows the release.

## 1.0.1-fold.107 (2026-11-01)

Fixed: the Claude launchers printed `ln: invalid option -- 'a'` at every start (Tab S10 FE,
fold.106). The native project key (`-data-user-0-...`) begins with a dash and `ln -s` read it as
options; now `ln -s --`. So the proot history link was never created; fold.105 blamed Claude Code
for removing it.

Tested: the failing and the fixed `ln` call with such a key (Git Bash); `check-launchers` passes.
On the Tab S10 FE (update over fold.106): starting Claude Code from the app created
`-root-projekty-Claude -> -data-user-0-...`, no error.

## 1.0.1-fold.106 (2026-11-01)

Changed:
- first install selects Termux's default mirror (Cloudflare CDN) unless one was chosen, skips
  Recommends and clang (80+ MB) but names the Recommends the desktop needs, Debian dpkg skips
  fsync and docs;
- the welcome screen asks for the language of the Linux apps; gettext finds the rootfs
  translations natively;
- Termux side: main-repo `mesa` (26.2.6) instead of TUR's `mesa-zink` (frozen at 22.0.5); older
  installs swap it in the background at desktop start, only when apt would remove nothing else;
  `LIBGL_KOPPER_DISABLE=true` on Adreno;
- the settings show the GPU's own name (GL_RENDERER, unwrapped from ANGLE);
- new `droiddesk-gpu-report` and `docs/gpu-test-kit.md`.

Found on Tab S10 FE: a clean install drew mirrors.pku.edu.cn at 19 kB/s (213 MB). Native Debian
programs stayed English with LANG=cs_CZ.UTF-8 (Czech under proot; Fold 7). Termux ships no
translations, so XFCE itself stays English. A clean install without Recommends had a black
desktop: xfdesktop is only a Recommends of xfce4-session (fixed, 15 packages named).

Tested on Tab S10 FE, clean install (`pm clear`, user 0):
- install 11:50 to 12:00 (under 10 minutes), packages-cf.termux.dev; the language picker
  preselected Čeština, cs_CZ.UTF-8 was generated; `ls --help` and `date` in Debian print Czech
  natively (`apt-get --help` stays English);
- the mesa-zink swap ran by itself at the next desktop start and removed only mesa-zink;
- the missing Recommends list comes from this install (installed by hand there, then the desktop
  had its wallpaper and icons again);
- second clean install with the named Recommends (15:20 to 15:29): mesa 26.2.6 and xfdesktop
  installed, the desktop came up with wallpaper and icons on the first start; it still lacked
  the Recommends of the added packages (dconf, glib-networking, file-roller, zenity), named too
  since then (that last list was installed by hand, not through a third clean install);
- settings show "Samsung Xclipse 540";
- GPU kit, virgl off: Termux llvmpipe GL 4.6, Firefox 159 WebGL ok at 2.1 FPS. Virgl on
  (`droiddesk-native-gpu on`): Termux virgl over ANGLE/Vulkan (GL 2.1, GLES 3.1), Firefox WebGL ok
  at 56.9 FPS. Debian with `droiddesk-gpu on`: virgl works (eglinfo renderer virgl/ANGLE, glxgears
  192 FPS against 622 on llvmpipe), but `glxinfo -B` fails with BadMatch (X_GetImage), native and
  under proot: it never maps its window, and Debian's Mesa 25.0.7 reads it back (Termux's Mesa
  26.2.6 does not). The GPU kit (v3) adds a glxgears run for that reason. Both switched off again
  after the test.

Tested on Fold 7 (Android 17) with the GPU kit, from Debian:
- Debian: zink on Turnip, GL 4.6, Mesa 26.2.6; Vulkan Adreno 830;
- Termux before the swap (mesa-zink 22.0.5): zink GL 4.6; Firefox 158 WebGL 117.6 FPS, Chromium
  156 WebGL 114.8 FPS; after the swap (mesa 26.2.6): zink on Turnip GL 4.6, Firefox 114.9 FPS,
  Chromium 106.3 FPS; the desktop and scrolling looked fine;
- Chromium WebGL flickered with artefacts through kopper; same page with
  LIBGL_KOPPER_DISABLE=true: clean, 58.9 instead of 86.8 FPS;
- OrcaSlicer (Debian): GL 4.6 on zink, a model loaded and rotated;
- glmark2 varies too much between runs to compare (Debian 235 to 719 with the same settings);
- not tested: Electron (none installed), video playback (needs a person watching).

Not tested: a clean install on the Fold; Mali GPUs.

## 1.0.1-fold.105 (2026-11-01)

Note: the APK of this release still reports versionName 1.0.1-fold.104 (versionCode 105); the
version bump was skipped by a failing command chain. The code is the fold.105 change.

Tested on Fold 7 after the update: the native history directory holds all 19 sessions (including
the old proot ones) and the memory notes. The proot directory link is removed again by Claude Code
(it deletes symlinks in ~/.claude/projects); a proot session then starts its own directory, which
the next native start merges.

## 1.0.1-fold.104 (2026-10-31)

Tested on Fold 7 with a 49" monitor over DeX (3840x984, work area 3840x919), by hand from the
native Claude Code session:

- `droiddesk-zones` (script copy in ~/bin, wmctrl from `apt-get download`): layout 25|50|25 =
  0..960..2880..3840; zones 1, 2, 3, 1-2, right, left from a maximized window: frame on the zone's
  left and top edge, no overlap with the panel (xfce4-terminal rounds the size to whole cells).

Not tested: the shortcuts Super+Ctrl+1..5/Left/Right and debian-setup 20 (wmctrl, xdotool,
x11-utils) from the release APK; windows without size increments.

## 1.0.1-fold.103 (2026-10-31)

Tested on Tab S10 FE (native Claude Code session over Remote Control, builds 5291d48–2bc8ddf):

- `sudo apt-get install` / `remove` of a package and `apt-cache ... | head` from the native Bash
  tool: run under proot with fake root, no proot messages on stderr.
- Background Claude Code update under proot: 2.1.314 → 2.1.316, success stamp written, lock removed.
- debian-setup 18: ripgrep installed, `NO_AT_BRIDGE=1` in Debian login shells;
  `USE_BUILTIN_RIPGREP=0` reaches Claude; Debian `rg` sees `/etc` and `/usr`.
- `--append-system-prompt` note: seen by a fresh native `claude -p`.
- Regressions: git, codex, `/system/bin/sh`, GoogleWorkspace MCP.
- `mkdir` of a path with a trailing slash (meson install on the Fold 7 failed): container test.
- History merge of a separate native project directory: simulated in a Debian container
  (sessions, hidden files, memory notes with a name clash kept as `.native`).

Tested on Fold 7: Mesa 26.2.6-1 (new GPU asset) from its staging tree: glxinfo on zink/Turnip
(Adreno 830), glxgears, glmark2 GLX score 1916 (crashed before).

Not tested: the release APK with the trailing-slash fix on a device (container test only);
the Mesa replacement through debian-setup 19; the history merge on the Fold 7 itself (that is where it is needed; checked after the
update); a resumed session seeing the system prompt note; Wine; Electron apps.

## 1.0.1-fold.102 (2026-10-30)

Tested on Tab S10 FE (native Claude Code session over Remote Control):

- `ls /`, `find / -name debian_version`, `cd /` with relative paths, `pwd` and `/bin/pwd`,
  `cd ..` at the root.
- Python `os.listdir('/')`, `os.chdir('/')`, `os.stat(..., dir_fd=open('/'))` for `proc/self/status`
  and `etc/debian_version`.
- `find /usr -type f` (79,914 files) in 0.3 s.
- Regressions: git, codex, `/system/bin/sh`, GoogleWorkspace MCP.

Not tested: Fold 7; the release APK itself (same code as the tested build, version number only).

## 1.0.1-fold.101 (2026-10-30)

Tested on Tab S10 FE:

- Native Claude Code via `claude-tmux` with Remote Control (reconnect after `/exit` and
  `--continue`), DNS in the Bash tool, GoogleWorkspace MCP over npx.
- Node `fs.stat` on Debian paths, `fs.mkdtemp`, `fs.watch`; Python `os.system`, `os.popen`,
  `tempfile`; `pgrep` by program name.
- Static programs under proot: codex (musl), esbuild (Go) from the Termux home with Debian paths.
- `/system/bin/sh` and toybox from native programs; OrcaSlicer; git `gc` and `fsck`.

Not tested: Fold 7; Wine; Electron apps after the hook changes.

## 1.0.1-fold.100 (2026-10-30)

Tested on Tab S10 FE overnight: git, node, python, codex, tmux and Claude Code natively; Brave,
Claude Desktop (Electron mirror, Debian keyring), mpv, OrcaSlicer, SolidCraft, FuCad natively;
apt, dpkg, sudo and Wine under proot.

Not tested: Fold 7; Claude Desktop picking up an existing login.

## Template

```
## VERSION (DATE)

Tested on DEVICE (how: adb, native session, by hand):
- ...

Not tested: ...
```
