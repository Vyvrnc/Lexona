# targetSdk 28 -> 36: implementation plan

Status: plan only, nothing implemented. Branch `lexona`, app id `io.github.vyvrnc.lexona`.

## Why

Play Protect on Android 16 blocks new installs of the app as "built for an older Android
version". This was seen on a Galaxy A16 (MediaTek, Mali) on 2026-11-11. The app targets SDK 28
on purpose (app/android/app/build.gradle.kts, defaultConfig), because from targetSdk 29 SELinux
denies `execute_no_trans` on app_data_file (W^X).

Probe results from commit 74fb519 (tools/exec-probe, Samsung tablet, targetSdk 36):
- A direct exec of an app-data ELF fails with EACCES.
- A glibc program starts through the patched ld.so shipped as `libld.so` in nativeLibraryDir.
  This also works from a running glibc program.
- A bionic program starts through `/system/bin/linker64 <path>`.
- mmap and dlopen of app-data libraries work, so LD_PRELOAD of `$PREFIX/lib/libsocket_hook.so`
  keeps working.

No data migration is needed: new app id, clean installs.

## What has to change (inventory)

Exec sites in Kotlin (all must go through one helper):
- LinuxRuntime.kt: about 30 `ProcessBuilder` calls. They start `$PREFIX/bin/bash`
  (killDesktopShell, openWithLinuxApp, refreshNativeSetup, swapMesaZink, refreshDebianSetup,
  runGpuSelfTest, startDebianSessionBus, runQuickCommand, startSession, ensurePulseAudio,
  executeCommand, the waitForDesktopReady check), `apt-get`, `clang` (compileSocketHook), xclip,
  notify-send, the dbus command, the screen-profile script (applyScreenProfile, a shebang
  script), the patched virgl server (`$PREFIX/libexec/droiddesk-virgl-server`), and the
  commands of ensureDefaultLook.
- view/TerminalActivity.kt `TerminalSessions.sessionFor`: TerminalSession (termux
  terminal-view JNI fork+execvp) of `$PREFIX/bin/bash` with argv `-bash`, start-debian,
  claude-tmux, codex-debian.
- Not affected (system binaries): MainActivity getprop, RootfsManager toybox tar,
  RootShell/ChrootRuntime su.

Exec in the Termux userland (app/assets/socket_hook.c, prebuilt as
jniLibs/arm64-v8a/libsocket_hook.so by tools/build-socket-hook.sh, copied to `$PREFIX/lib` by
LinuxRuntime.ensureSocketHookPrebuilt and loaded through `LD_PRELOAD` from getTermuxEnv):
- It hooks execve, execv, execvp and execvpe only, with the com.termux path rewrite,
  exec_termux_script and exec_relocated_maintainer_script.
- It does not hook execl, execlp, execle, fexecve, posix_spawn or posix_spawnp.

Exec in the Debian native path (tools/glibc-native/pathhook.c, shipped as
assets/droiddesk/glibc-native/pathhook.so):
- `prepare()` routes glibc ELFs through `$DD_PLIB/ld.so`.
- Bionic ELFs are exec'd directly (`c->file = target`), so Termux programs started from Debian
  would fail.
- prepare_proot uses `$PREFIX/bin/proot` and `$PREFIX/libexec/proot/loader` from app data.

Launcher assets/droiddesk/droiddesk-glibc-native:
- It patches ld.so and libc on the device from the rootfs (`setup`: patch-glibc.py into `$PLIB`).
- It execs `$PLIB/ld.so` (about lines 70, 289, 331, 481 and 500).
- `patch_one` sets PT_INTERP to `$PLIB/ld.so`.

proot:
- The generated launchers (start-debian, debian-apps, claude-debian, codex-debian, debian-run,
  … in LinuxRuntime.writeDebianLauncher and friends) pass
  `PROOT_LOADER=$PREFIX/libexec/proot/loader` and `PROOT_LOADER_32`.
- `proot-distro` calls the Termux `proot` package binary.
- jniLibs already contains `libproot.so`, `libproot-loader.so`, `libtalloc.so` and
  `libandroid-shmem.so`, but nothing uses them. Their source and licences are listed as release
  blockers in THIRD_PARTY_NOTICES.md and COMPLIANCE.md.

Process identity:
- desktopProcessAlive reads `/proc/*/comm`.
- killDesktopShell and pulseStartScript use `pkill -x`.
- waitForDesktopReady uses `pgrep -x`.
- killStaleVirglServers compares cmdline argv[0] with the patched path.
- With linker64, comm is "linker64" and cmdline[0] is whatever argv[0] the linker got.

## Design decisions

1. **Extend socket_hook.c; do not load termux-exec.**
   - Bootstrap already ships termux-exec 2.5.0 (`lib/libtermux-exec*.so`,
     `bin/termux-exec-system-linker-exec`).
   - termux-exec has a system-linker-exec mode
     (TERMUX_EXEC__SYSTEM_LINKER_EXEC__MODE=enable|force|disable). It reads TERMUX__PREFIX,
     TERMUX__ROOTFS and TERMUX_APP__DATA_DIR, decides from `/proc/self/attr/current`
     (untrusted_app_25/27 means exempt), exports `TERMUX_EXEC__PROC_SELF_EXE` to children, and
     refuses an argv[0] of 128 characters or more on some SDKs.
   - Chaining it after our hook (LD_PRELOAD order socket_hook:termux-exec) is possible, but it
     adds a second execve interposer. It has its own app-data-dir detection and shebang
     rewriting, which overlap with our com.termux relocation and maintainer-script copy. It
     also cannot fix comm or argv[0], and apt can upgrade it independently.
   - Decision: implement linker exec in our hook, with termux-exec's semantics as the reference.
     Use its installed tests (`libexec/installed-tests/termux-exec/.../exec-intercept_runtime-script-tests`,
     print-args-binary, print-args-*-script.sh) as an oracle against our hook.
   - Set `TERMUX_EXEC__SYSTEM_LINKER_EXEC__MODE=disable` in getTermuxEnv, so a termux-exec loaded
     by some Termux profile never double-wraps. A double wrap would be harmless anyway, because
     linker64 is not under app data.
2. **Keep the hook in LD_PRELOAD from `$PREFIX/lib/libsocket_hook.so` (copy), not from
   nativeLibraryDir.**
   - nativeLibraryDir changes on every app update (`/data/app/~~…/lib/arm64`), so long-lived
     env values and generated scripts would hold stale paths.
   - init_hook_prefix derives the prefix from the hook's own path; a hook loaded from
     nativeLibraryDir would fall back to the compiled NEW_PREFIX.
   - The first process is still started as `/system/bin/linker64 $PREFIX/bin/bash …` with
     LD_PRELOAD set.
   - If the hook ever must load from nativeLibraryDir (before the copy exists), add a fallback
     in init_hook_prefix: env `DROIDDESK_PREFIX`, then `PREFIX`, then NEW_PREFIX.
3. **Stable pointer to nativeLibraryDir.** At each app start, write
   `$PREFIX/etc/droiddesk/native-lib-dir` (one line) and export `DROIDDESK_NATIVE_LIB_DIR` in
   getTermuxEnv. Wrappers and pathhook use the env value first, then the file.
4. **One exec decision table**, shared in spirit by socket_hook.c, pathhook.c and NativeExec.kt:
   - ELF, PT_INTERP /system/bin/linker64, file under the app data dir (`/data/data/<pkg>/`,
     `/data/user/<n>/<pkg>/`, after realpath):
     `execve("/system/bin/linker64", [orig_argv0, path, args…])`.
   - `#!` script under app data: parse the interpreter as today (with the com.termux rewrite),
     then apply the table recursively to the interpreter with argv
     `[interp, (arg), script, args…]`. A system interpreter (`/system/bin/sh`) is exec'd
     directly with the script as an argument. The kernel never execs the script file itself,
     because that also needs execute_no_trans.
   - glibc ELF (interp /lib/ld-linux-aarch64.so.1 or `$DD_PLIB/ld.so`) started from the Termux
     side: unchanged policy (the launchers decide). If exec'd, it goes through
     `$DROIDDESK_NATIVE_LIB_DIR/libld.so`.
   - Static ELF under app data: cannot run. Return EACCES and log once. The only static helper
     we need (the proot loader) lives in nativeLibraryDir.
   - Anything else (/system, /apex, /vendor, nativeLibraryDir): `real_execve` unchanged.
   - Fallback: if `real_execve` returns EACCES for a path not caught above (for example a
     symlink into app data from elsewhere), retry once through the table.
5. **Restoring identity in the child**: a hook constructor that runs in every hooked process.
   Bionic passes (argc, argv, envp) to DT_INIT_ARRAY functions of preloaded libraries; verify
   this on the A16.
   - If `/proc/self/exe` resolves to `/system/bin/linker64`, read `/proc/self/cmdline`.
     Element 0 is the original argv[0] (we give it to the linker, which ignores it); element 1
     is the real program.
   - Store the real program in `self_exe`. Set `argv[0]` to a static copy of the original
     argv[0], so `-bash` login shells, `exec -a` and multi-call names survive.
   - Call `prctl(PR_SET_NAME, basename(orig_argv0))`, so comm, pgrep -x and pkill -x keep
     working. pathhook.c already does the same for ld.so (find_self_exe); reuse that code.
   - Intercept `readlink`/`readlinkat` of `/proc/self/exe`, `/proc/thread-self/exe` and
     `/proc/<getpid()>/exe` to return self_exe. Users include libuv uv_exepath (node, npm),
     Chromium/Electron/Firefox re-exec and Python sys.executable fallbacks.
   - Also intercept `realpath` of those, `open` of `/proc/self/exe` (programs reading their own
     ELF), and `execve("/proc/self/exe", …)` (it becomes exec of self_exe through the table).
   - Processes started without the hook (virgl server with a cleared env, `env -i` children)
     keep comm "linker64". Kotlin matches those by cmdline[0], which NativeExec sets to the
     program path.

## Phase 0: build switch and test harness

Goal: build 28 and 36 from the same HEAD and drive the A16 over wireless adb.

Changes:
- app/android/app/build.gradle.kts:
  - `val sdk = (project.findProperty("lexona.targetSdk") as String?)?.toInt() ?: 28`, then
    `targetSdk = sdk`, and `compileSdk = 36` explicitly (AGP 8.11.1 and Gradle 8.14 support
    it). Keep minSdk 28.
  - `buildConfigField("int", "EXEC_TARGET_SDK", "$sdk")` (enable `buildFeatures.buildConfig`).
  - Optional `lexona.appIdSuffix` (for example `.t36`), so the tablet can keep the 28 build
    installed next to a 36 build. The hook takes its prefix from its own path, so a different
    id works.
  - Optional `lexona.debuggable=true` on the release type for test builds only. `run-as` then
    runs in the app's real SELinux domain (untrusted_app at 36), which keeps adb testing honest.
- tools/build-apk.sh: pass `TARGET_SDK`, `APP_ID_SUFFIX` and `DEBUGGABLE` env as
  `flutter build apk --release --android-project-arg=lexona.targetSdk=$TARGET_SDK …`. Name the
  output `Lexona-sdk$TARGET_SDK.apk`.
- At runtime, decide by `applicationInfo.targetSdkVersion >= 29` (not by BuildConfig), so the
  same code path is tested in both builds.
- LinuxRuntime: on each start, write `$PREFIX/etc/droiddesk/adb-env.sh` (`export K='V'` lines
  from getTermuxEnv plus DROIDDESK_NATIVE_LIB_DIR), for test sessions.
- tools/exec-probe: add cases for:
  - posix_spawn through the hook;
  - argv[0] and comm after linker exec;
  - readlink /proc/self/exe;
  - LD_PRELOAD of an app-data .so into /system/bin/sh;
  - memfd_create and /dev/ashmem open;
  - getifaddrs and /proc/net/dev.

Risks:
- `--android-project-arg` must reach the app module. Check `./gradlew -q properties` inside
  the build container.
- A debuggable test APK differs from the shipped one only in that flag. Run the final checks on
  a non-debuggable build too.

Test on the A16:
```
TARGET_SDK=36 DEBUGGABLE=true tools/build-apk.sh
adb connect <a16-ip>:<port>
adb install -r ~/DroidDesk-build/Lexona-sdk36.apk
adb shell dumpsys package io.github.vyvrnc.lexona | grep -E 'targetSdk|versionName'
adb shell run-as io.github.vyvrnc.lexona cat /proc/self/attr/current      # expect u:r:untrusted_app:s0:..., not _27
bash tools/exec-probe/build.sh && adb install -r tools/exec-probe/out/exec-probe.apk
adb shell am start -n com.vyvrnc.execprobe/.MainActivity; adb logcat -s ExecProbe
```
Expected: the same results as on the tablet (A fails, B/C/D/E work). The new cases document
what the hook must provide. Also note in docs/VERIFICATION.md whether Play Protect accepts the
36 build on the A16 (install from a file manager, not adb, to see its dialog).

## Phase 1: smoke test, bootstrap + bash + apt at 36

Goal: on a clean install on the A16, the app extracts the bootstrap, and `bash`, `apt update`,
`apt install`, `pkg install` and dpkg maintainer scripts work. No desktop yet.

Changes:
1. New file app/android/app/src/main/kotlin/com/orailnoor/droiddesk/runtime/NativeExec.kt:
   - `fun command(ctx, argv: List<String>): List<String>` applies the decision table in Kotlin
     (read the ELF header and PT_INTERP, or the `#!` line). It returns
     `["/system/bin/linker64", argv0Path, …]`, checks the argv[0] length and logs.
   - `fun processBuilder(ctx, argv, env)` sets the env (always including LD_PRELOAD from
     getTermuxEnv) and returns a ProcessBuilder.
   - When targetSdk < 29 it returns argv unchanged, so the 28 build behaves as today.
2. LinuxRuntime.kt: replace every `ProcessBuilder(...)` that starts an app-data program with
   NativeExec.
   - Start with executeCommand, the bootstrap and setup paths (`installRepoPackages`,
     `installPackageGroup`, `repairPackageState`, `compileSocketHook`; extractBootstrapIfNeeded
     has no exec) and runQuickCommand.
   - Done when `grep -n "ProcessBuilder(" LinuxRuntime.kt` shows only NativeExec or system
     binaries.
3. view/TerminalActivity.kt TerminalSessions.sessionFor: shell `/system/bin/linker64`, args
   `["-bash", "$bin/bash"]`.
   - The hook constructor restores `-bash` from cmdline[0]. Before the constructor is verified,
     use `["bash", "$bin/bash", "-l"]`.
   - For start-debian, claude-tmux and codex-debian (bash scripts):
     `["start-debian", "$bin/bash", "$bin/start-debian"]`.
4. app/assets/socket_hook.c:
   - `exec_via_table()` implements decisions 4 and 5. Use it from:
     - execve, execv, execvp (PATH search done in the hook, honouring access X_OK, which passes
       for app-data files) and execvpe;
     - new execl, execlp and execle (vararg to argv, like pathhook exec_list);
     - fexecve (`/proc/self/fd/N` and readlink to path);
     - posix_spawn and posix_spawnp (rewrite file and argv, then call the real posix_spawn on
       linker64; file actions and attrs pass through).
   - The existing exec_relocated_maintainer_script and exec_termux_script must end in
     exec_via_table, not real_execve, because their interpreter is also in app data.
   - Add the constructor described in decision 5, plus readlink/readlinkat/realpath/open
     handling of /proc/self/exe.
   - Keep everything gated, so the 28 build behaves byte-identically. The gate is either
     "running in an untrusted_app domain that is not _25/_27" (read `/proc/self/attr/current`
     once) or env `DROIDDESK_LINKER_EXEC=1`, set by getTermuxEnv when targetSdk >= 29.
   - Rebuild with tools/build-socket-hook.sh and extend its `llvm-nm` check to the new symbols.
5. LinuxRuntime.compileSocketHook: the on-device clang path must compile the same source. It
   runs clang through NativeExec; clang spawns ld.lld through posix_spawn, which tests the hook.
6. getTermuxEnv: add `DROIDDESK_LINKER_EXEC`, `DROIDDESK_NATIVE_LIB_DIR`, `DROIDDESK_PREFIX` and
   `TERMUX_EXEC__SYSTEM_LINKER_EXEC__MODE=disable`.

Approach notes:
- Bash's `exec -a NAME` and login shells rely on the constructor. Test both.
- The argv[0] length limit (termux-exec message "argv[0] length >= 128 while running on Android
  SDK %d"):
  - Our prefix `/data/user/0/io.github.vyvrnc.lexona/files/usr` is 46 characters, so deep paths
    (Python venvs, node_modules/.bin) can exceed 128.
  - Find out which SDKs are affected from the termux-exec source. If Android 16 is one of them,
    pass a short symlink path from `$PREFIX/tmp/x/` instead.

Risks:
- Bionic's own internal calls (execlp inside libc, posix_spawn calling execve) may bypass PLT
  interposition. Hooking every public entry point covers this.
- Go binaries and anything using raw `syscall(SYS_execve)` bypass the hook. Examples: Termux
  `gh`, `rclone` and `lazygit` spawning children. Document them as known limitations and test
  one.
- Processes that clear LD_PRELOAD and then exec app-data files: `env -i` is fine, because env
  itself is hooked when it execs.
- linker64 cannot start non-PIE executables. Termux builds are PIE.

Test on the A16 (clean install of the 36 build, debuggable):
```
adb uninstall io.github.vyvrnc.lexona; adb install Lexona-sdk36.apk
# open the app, let it bootstrap (or trigger the setup screen), then:
P=/data/user/0/io.github.vyvrnc.lexona/files/usr
adb shell run-as io.github.vyvrnc.lexona sh -c ". $P/etc/droiddesk/adb-env.sh; $P/bin/bash -c true; echo direct=\$?"   # expect 126 (EACCES)
adb shell run-as io.github.vyvrnc.lexona sh -c ". $P/etc/droiddesk/adb-env.sh; exec /system/bin/linker64 $P/bin/bash -lc '
  echo bash=\$BASH_VERSION; readlink /proc/\$\$/exe; cat /proc/\$\$/comm;
  apt update && apt install -y python nano && python3 -c \"import os,subprocess;print(os.readlink(\\\"/proc/self/exe\\\"));print(subprocess.run([\\\"ls\\\",\\\"-d\\\",\\\"/\\\"]).returncode)\";
  sh -c \"exec -a fakename sleep 30\" & sleep 1; pgrep -x fakename; pgrep -x sleep; kill %1;
  dpkg --configure -a; echo DONE'"
adb logcat -d | grep -iE 'avc: denied.*execute_no_trans|socket_hook' | tail
```
Pass criteria:
- `apt update` and `apt install` succeed, including postinst scripts.
- readlink prints the real bash and python paths, not linker64.
- comm is `bash`.
- `pgrep -x fakename` finds the process.
- No execute_no_trans denials other than the deliberate direct-exec check.
- The in-app terminal opens a login shell (prompt from `$PREFIX/etc/profile`).

## Phase 2: Termux desktop at 36

Goal: the native XFCE session starts on the A16, with sound, the terminal, Firefox and virgl
(Mali: llvmpipe or virgl over ANGLE).

Changes:
- LinuxRuntime.kt:
  - The remaining ProcessBuilder sites go through NativeExec: startSession, the dbus start,
    ensurePulseAudio, applyScreenProfile, openWithLinuxApp, the xclip read/write,
    notifyDesktop, killDesktopShell, ensureDefaultLookInBackground,
    refreshNativeSetupInBackground, swapMesaZinkInBackground, ensureVirglServerInBackground and
    runGpuSelfTest.
  - The patched virgl server starts via linker64 with argv0 = the patched path, so
    killStaleVirglServers still matches cmdline[0].
  - desktopProcessAlive compares comm, and falls back to the basename of cmdline[0].
- Generated launcher scripts (shebang `#!$PREFIX/bin/bash`): no change in content. The hook
  starts them through the bash interpreter. Kotlin starts them with
  `NativeExec.command(listOf(script, …))`, which reads the shebang.
- processPid() uses reflection on the private `pid` field of the libcore Process
  implementation. Check that it still works at 36 (hidden-API lists depend on targetSdk). If it
  does not, start commands through `bash -c 'echo $$ >&3; exec …'`, or find the child by
  walking `/proc/<ourpid>/task/*/children`.
- libXlorie.so (in process) must not exec app-data programs. Check `xkbcomp` and the keymap:
  look for `xkbcomp` in logcat, then switch the layout in XFCE.

Risks:
- MIT-SHM and PulseAudio shared memory through Termux libandroid-shmem (/dev/ashmem) may be
  denied for untrusted_app at 29+.
  - Symptoms: X clients fail on XShm (xfwm4, Firefox) and Pulse refuses clients.
  - Fixes: switch to memfd (newer libandroid-shmem), or turn shm off
    (`XLIB_SKIP_ARGB_VISUALS`/`MIT-SHM` off in Lorie, Pulse `enable-shm=no`).
- getifaddrs and netlink RTM_GETLINK are restricted from targetSdk 30. NetworkManager-like
  tools, node os.networkInterfaces() and `ip link` may fail. Test them, and hook getifaddrs to
  an RTM_GETADDR-only path if needed.
- `/proc/net/*` is unreadable from targetSdk 29 (netstat, ss, some panel plugins).

Test on the A16:
```
adb install -r Lexona-sdk36.apk; adb shell am start -n io.github.vyvrnc.lexona/com.orailnoor.droiddesk.MainActivity
# start the desktop in the UI, then:
adb shell run-as io.github.vyvrnc.lexona sh -c ". $P/etc/droiddesk/adb-env.sh; exec /system/bin/linker64 $P/bin/bash -lc '
  pgrep -x xfce4-session && pgrep -x xfwm4 && pgrep -x pulseaudio; pactl info | head -3;
  DISPLAY=:0 xdpyinfo -ext MIT-SHM | grep -i shm; DISPLAY=:0 glxinfo -B | grep renderer;
  node -e \"console.log(process.execPath, Object.keys(require(\\\"os\\\").networkInterfaces()))\" ;
  ip -br addr; cat /proc/net/dev | head -2'"
adb logcat -d | grep -E 'avc: denied' | sort | uniq -c | sort -rn | head -20
```
Manual checks:
- XFCE panel and menu;
- xfce4-terminal (VTE spawns through posix_spawn or g_spawn);
- Thunar opening a file with "Open With";
- Firefox loading a page (content processes re-exec through /proc/self/exe);
- sound from Firefox;
- the in-app terminal profiles;
- desktop restart from the app (killDesktopShell plus waitForDesktopReady).

## Phase 3: native helpers in jniLibs

Goal: every program that must be exec'd directly (not through linker64 or ld.so) lives in
nativeLibraryDir and is named lib*.so.

What goes into app/android/app/src/main/jniLibs/arm64-v8a:
- `libproot.so`, `libproot-loader.so`, `libtalloc.so` (already present).
  - Rebuild them from termux/proot (and talloc) at one recorded commit, with a script in
    tools/ (for example tools/build-proot.sh, same pattern as build-socket-hook.sh).
  - proot and its loader must be the same build (private protocol). This also clears the
    licence blockers in THIRD_PARTY_NOTICES.md and COMPLIANCE.md.
  - The loader is static and cannot run through linker64, so it must be here.
- `libld.so`: the patched Debian glibc ld.so (Phase 5).
- `libsocket_hook.so` (already present, copied to `$PREFIX/lib`).
- Not needed: bash, busybox, toybox. Kotlin extracts the bootstrap (ZipInputStream,
  Os.symlink), and linker64 runs bash from app data. `libandroid-shmem.so` stays as is (it is
  loaded, not exec'd).

Packaging:
- Keep `packaging { jniLibs.useLegacyPackaging = true }`, which gives extractNativeLibs=true.
  Without it the libraries stay inside the APK and cannot be exec'd.
- Add assertions in build-apk.sh: `aapt2 dump xmltree --file AndroidManifest.xml` must not show
  extractNativeLibs false, and `unzip -l` must list each lib*.so.
- `libld.so` and `libproot.so` are executables named .so. AGP strips debug symbols (fine) and
  may warn. `doNotStrip` is not needed.
- Size: about +0.25 MB compressed for libld.so. proot, the loader and talloc are already in the
  APK.
- 16 KB page size: link new helpers with `-Wl,-z,max-page-size=16384` (pathhook already does
  this) and check the existing libs with `llvm-readelf -l`. This only matters on 16 KB devices;
  the A16 uses 4 KB.

Kotlin: write `$PREFIX/etc/droiddesk/native-lib-dir` and keep `$PREFIX/bin/proot` as a wrapper
script (Phase 4).

Test:
1. Find the library directory: `adb shell run-as <pkg> ls -l $(dirname of applicationInfo.nativeLibraryDir)/`
   (print the path from the app log or from adb-env.sh).
2. `adb shell run-as <pkg> sh -c '. …/adb-env.sh; $DROIDDESK_NATIVE_LIB_DIR/libproot.so --version'`
   must start directly, with no linker64.

## Phase 4: proot (Debian container) at 36

Goal: proot-distro installs Debian, and start-debian, debian-run, debian-apps and the
claude/codex launchers work, including apt inside Debian.

Approach (as UserLAnd, Winlator and other targetSdk 29+ apps do):
- proot runs from nativeLibraryDir, and `PROOT_LOADER` points to `libproot-loader.so` there.
- proot turns every tracee execve into an exec of the loader, which maps the guest ELF with
  mmap. Guest binaries in the rootfs are never exec'd by the kernel, so W^X does not hit them.
- `PROOT_LOADER_32` is dropped (arm64 only).

Changes:
- Replace the Termux proot package binary with a wrapper.
  - Divert it once: `dpkg-divert --local --rename --divert $PREFIX/bin/proot.termux --add $PREFIX/bin/proot`.
  - Then write `$PREFIX/bin/proot`:
    `#!$PREFIX/bin/bash` / `d=${DROIDDESK_NATIVE_LIB_DIR:-$(< $PREFIX/etc/droiddesk/native-lib-dir)}` /
    `export PROOT_LOADER=$d/libproot-loader.so LD_LIBRARY_PATH=$d${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}` /
    `unset PROOT_LOADER_32` / `exec "$d/libproot.so" "$@"`.
  - Rewrite it at every app start, next to wrapDpkgForPath/wrapUpdateAlternatives in
    LinuxRuntime.
- LinuxRuntime.kt: change all `--env PROOT_LOADER=… --env PROOT_LOADER_32=…` blocks
  (writeDebianLauncher, debian-apps, the claude/codex launchers and the run launcher; about
  lines 563, 588, 727, 809, 1027 and 1060).
  - Set `PROOT_LOADER="$DROIDDESK_NATIVE_LIB_DIR/libproot-loader.so"` and remove
    `PROOT_LOADER_32`.
  - Take the value from the environment at script run time, not baked in, because
    nativeLibraryDir changes on update.
- relocateProotExecutable becomes obsolete for the jniLibs build. Keep it for 28.
- proot-distro may check `proot` with `--version` or use `PROOT_NO_SECCOMP`. Keep the env of
  today's launchers.

Risks:
- The proot version differs from the Termux proot that proot-distro 5.x was tested with. Use a
  recent termux/proot commit.
- ptrace and seccomp behaviour of the untrusted_app domain at 36: if proot is slow,
  `PROOT_NO_SECCOMP=1` is the knob.
- Hard links inside proot need `--link2symlink`. proot-distro passes it.

Test on the A16:
```
# in-app: install Debian (or: run-as … bash -lc 'proot-distro install debian')
adb shell run-as <pkg> sh -c ". $P/etc/droiddesk/adb-env.sh; exec /system/bin/linker64 $P/bin/bash -lc '
  proot --version; start-debian -c true 2>&1 | tail -2;
  debian-run bash -c \"uname -a; apt-get update && apt-get install -y hello && hello; ls -l /proc/self/exe\"'"
```
Also open the "debian" terminal profile and run `sudo apt install -y htop`. In XFCE, start a
Debian app from the menu (debian-apps).

## Phase 5: glibc native Debian at 36

Goal: droiddesk-glibc-native runs Debian programs natively through `libld.so` from
nativeLibraryDir. Its exec chains work: glibc to glibc, glibc to bionic Termux, and glibc to
proot for static/musl/apt.

Approach:
- ld.so can no longer be patched on the device into an executable location. Build it at APK
  build time from a pinned Debian trixie glibc, exactly as tools/exec-probe/build.sh does:
  `patch-glibc.py ld /usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 jniLibs/arm64-v8a/libld.so`.
- Ship the matching patched `libc.so.6` as an asset (it is mmap'd, so app data is fine) and copy
  it to `$PLIB` at setup.
- ld.so and libc share GLIBC_PRIVATE internals and must be the same build. Ship the rest of the
  glibc runtime from the same build into `$PLIB` too (libm, libresolv, libpthread, libdl, librt,
  libutil, libanl, libnss_files, libnss_dns). `$PLIB` is already first in LIBPATH, so it then
  never mixes builds with the rootfs.
- New script tools/glibc-native/build-loader.sh. Record the Debian glibc version in the script
  and in COMPLIANCE.md.
- Alternative, if pinning hurts: a tiny static "userland exec" stub `libddexec.so` in
  nativeLibraryDir.
  - It maps the on-device patched `$PLIB/ld.so` from app data (mmap PROT_EXEC is allowed) and
    jumps to its entry with a rebuilt auxv, the same technique as the proot loader.
  - That keeps today's on-device patching and the coupling to the rootfs.
  - It is more code, and pathhook's is_loader and find_self_exe must recognise it.

Changes:
- tools/glibc-native/pathhook.c:
  - New env `DD_LOADER` (absolute path of libld.so). `is_loader()` accepts DD_LOADER and the old
    `$DD_PLIB/ld.so`. The glibc branch of `prepare()` uses `DD_LOADER`.
  - The bionic branch: if the target is under the app data dir, emit `/system/bin/linker64` with
    argv `[argv0, target, …]`. The socket_hook constructor restores argv0 and comm.
  - Treat PT_INTERP == `$DD_PLIB/ld.so` (patchelf'd mirrors from patch_one) as glibc. Today it
    counts as "unknown", which goes to proot.
  - prepare_proot uses `$DROIDDESK_NATIVE_LIB_DIR/libproot.so` and `…/libproot-loader.so`, from
    DD_SAVED_* or a new `DD_NATIVE_LIB_DIR` variable.
  - glibc_system/popen build the `"$loader" --library-path …` string from DD_LOADER.
  - Rebuild with tools/glibc-native/build.sh.
- assets/droiddesk/droiddesk-glibc-native:
  - `setup()` no longer patches ld.so from the rootfs. It copies the shipped libc/glibc set into
    `$PLIB` and checks that `$DD_LOADER` exists. The stamp now includes the APK's libld.so hash.
  - Every `$PLIB/ld.so` exec (lines about 481 and 500, and the `ready()` checks) becomes
    `$DD_LOADER`.
  - Export `DD_LOADER` and `DD_NATIVE_LIB_DIR` in the `env -i` list (about line 479) and in the
    mirror `.dd-env` (about line 428).
  - `patch_one` keeps `--set-interpreter "$PLIB/ld.so"`. It is only a marker now; pathhook
    routes it.
- LinuxRuntime.kt writeDeviceTools (about line 1820): copy the shipped glibc set from assets to
  `opt/glibc-native/share/`, and drop the ld.so step's dependency on running python3
  patch-glibc.py on the device.

Risks:
- Debian security updates of libc6 do not reach native programs until an app update ships a
  new pair. Programs needing newer GLIBC_2.x symbols than the shipped build fail. The existing
  quick-exit fallback to proot catches most of them.
- patch-glibc.py patterns must match the pinned version. The build must fail loudly if they do
  not (the script already exits non-zero).
- Bun/Claude Code re-execs /proc/self/exe with argv0 "rg" (handled by find_self_exe). Re-test
  it.

Test on the A16:
```
adb shell run-as <pkg> sh -c ". $P/etc/droiddesk/adb-env.sh; exec /system/bin/linker64 $P/bin/bash -lc '
  droiddesk-glibc-native setup && droiddesk-glibc-native status;
  debian-run /usr/bin/python3 -c \"import os,subprocess;print(os.readlink(\\\"/proc/self/exe\\\"));subprocess.run([\\\"/usr/bin/ls\\\",\\\"/\\\"])\";
  debian-run bash -c \"$P/bin/uname -a\";            # glibc -> bionic Termux program via linker64
  debian-run apt-get -s install hello | tail -1      # proot-only route'"
```
Then start Claude Code natively from the menu or claude-tmux, and use Grep and Glob in it (rg
re-exec). Start a mirrored Electron app if one is installed.

## Phase 6: Android API changes between 28 and 36

Goal: no crashes or silent breakage from API behaviour gated on targetSdk. These items do not
depend on Phases 2–5 and can go in parallel after Phase 1.

1. **Foreground service** (AndroidManifest.xml, service/DroidDeskService.kt):
   - From targetSdk 35, dataSync is limited to 6 h per 24 h (`onTimeout`, then the app is
     stopped). Switch to `specialUse`:
     - `android:foregroundServiceType="specialUse"`;
     - `<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>`;
     - inside `<service>`: `<property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="Runs the user's Linux desktop session and its processes"/>`;
     - `ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE` in startForeground.
   - Add `microphone` as a second type (with permission FOREGROUND_SERVICE_MICROPHONE). Set it
     only while RECORD_AUDIO is granted and the app is in the foreground. Since targetSdk 34,
     recording from the background needs it (PulseAudio's AAudio/OpenSL source runs under our
     uid).
   - Do not add `camera`: CameraBridge runs only with the desktop in the foreground.
   - Remove FOREGROUND_SERVICE_DATA_SYNC.
   - Wrap startForeground in try/catch for ForegroundServiceStartNotAllowedException
     (START_STICKY restarts from the background), and stopSelf on failure.
   - Implement `onTimeout(int,int)` defensively.
2. **Notifications** (MainActivity.kt): request POST_NOTIFICATIONS at runtime on API 33+, in the
   existing permission chain (after storage, before microphone). Without it the service
   notification and the CameraBridge prompts are invisible.
3. **Storage** (runtime/SharedStorage.kt, manifest):
   - From targetSdk 30, requestLegacyExternalStorage is ignored. WRITE_EXTERNAL_STORAGE does
     nothing, and READ does nothing from 33.
   - Linux programs need POSIX access to /sdcard, so use MANAGE_EXTERNAL_STORAGE (already
     declared): check `Environment.isExternalStorageManager()`; otherwise open
     `Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` with a `package:` URI.
     linkIntoHome stays.
   - Add `android:maxSdkVersion="32"` to READ_EXTERNAL_STORAGE and `29` to
     WRITE_EXTERNAL_STORAGE.
   - /sdcard/Android/data stays inaccessible. Distribution is outside Play, so the Play
     all-files policy is not a blocker.
4. **Package visibility** (manifest `<queries>`):
   - AndroidAppBridge calls resolveActivity for ACTION_DIAL `tel:` and ACTION_SENDTO `smsto:`.
     Add those intents.
   - Keep MAIN/LAUNCHER (queryIntentActivities, getLaunchIntentForPackage) and PROCESS_TEXT.
     ACTION_VIEW through createChooser needs no visibility.
   - Test the Android-apps menu in XFCE.
5. **Receivers and PendingIntents**:
   - DroidDeskService `registerReceiver(batteryReceiver, ACTION_BATTERY_CHANGED)`: a system
     broadcast, so it is exempt. Switch to `ContextCompat.registerReceiver(…,
     RECEIVER_NOT_EXPORTED)` for clarity.
   - UsbBridge already uses RECEIVER_NOT_EXPORTED and a mutable PendingIntent with
     `setPackage`, which counts as explicit and is allowed at 34+.
   - CameraBridge and the service use FLAG_IMMUTABLE. No change.
6. **Edge-to-edge** (enforced at 35, no opt-out at 36):
   - MainActivity.restoreSystemBars `setDecorFitsSystemWindows(true)` and
     `window.statusBarColor` become no-ops.
   - Flutter screens without SafeArea or inset handling will draw under the status and
     navigation bars. Check each, including desktop_screen.dart, desktop_tools_screen.dart and
     gpu_support_screen.dart.
   - TerminalActivity: with edge-to-edge, `adjustResize` no longer shrinks the view. Apply
     `WindowInsets.Type.systemBars() | ime()` as padding in an OnApplyWindowInsetsListener;
     otherwise the keyboard covers the prompt.
   - DesktopActivity is already immersive. Check that the soft keyboard and the extra-keys bar
     still appear above the IME.
   - Remove `android:statusBarColor` from styles.xml (it is ignored).
7. **Predictive back**: `enableOnBackInvokedCallback="true"` is already set, so 36 changes
   nothing. Check that Back in DesktopActivity still reaches TouchInputHandler (KEYCODE_BACK).
8. **Large screens** (36): orientation and resizability requests are ignored at 600 dp and
   above. All activities already handle configChanges. Check that DeX and the tablet still keep
   the session (the Samsung keepalive meta-data stays).
9. **Background activity starts**: unchanged in principle since Android 10. From 35, launches
   are refused when another app's task is on top. Test droiddesk-open and
   `xdg-open https://…` from XFCE in DeX with another Android window focused.
10. **Hidden API**:
    - The LinuxRuntime.processPid reflection (see Phase 2).
    - SamsungDexUtils reflects on Samsung classes, which are not restricted.
    - `InputDevice.isExternal` is public API from 29; replace the reflection with a direct call
      when the API is 29+.
11. **Network**: Android 16 adds a local-network permission, enforced from 37. No change now.
    Once targetSdk 37 arrives, LAN access from Linux (ssh to a LAN host, droiddesk-net) will need
    `ACCESS_LOCAL_NETWORK`.
12. **ZipInputStream** (from 34): it rejects entry names with `..` or a leading `/`. Check
    extractZip on the bootstrap (names are relative). The `../` inside SYMLINKS.txt is content
    and is not affected.

Test on the A16:
- `adb shell dumpsys activity services io.github.vyvrnc.lexona | grep -E 'types=|isForeground'`
  shows specialUse.
- Leave the desktop running for more than 6 h. To confirm the old failure first, set
  `adb shell device_config put activity_manager data_sync_fgs_timeout_duration 60000` while
  still on dataSync, then repeat with specialUse.
- `adb shell dumpsys notification | grep lexona`.
- `adb shell appops get io.github.vyvrnc.lexona MANAGE_EXTERNAL_STORAGE`, then
  `ls ~/storage/shared` in the terminal.
- Screenshots (`adb exec-out screencap -p > s.png`) of each Flutter screen with gesture and
  3-button navigation.
- The terminal with the keyboard open.
- Android-apps menu entries launch apps.
- Microphone test: `parecord` while the app is in the background.

## Phase 7: switch the default and clean up

Goal: 36 is the shipped build. The 28 path stays reachable for one release, then goes.

Changes:
- build.gradle.kts defaults to `lexona.targetSdk=36`. Remove the W^X comment.
- build-apk.sh defaults to 36.
- After one release, delete the 28-only branches:
  - the `DROIDDESK_LINKER_EXEC` gate (linker exec becomes unconditional when the domain is not
    _25/_27);
  - relocateProotExecutable;
  - the on-device ld.so patch path.
- README and APP_TROUBLESHOOTING.md get a known-limitations list:
  - Go and static programs that exec children;
  - processes started without the hook;
  - ps showing linker64 for processes started without the hook;
  - delayed glibc security updates.
- docs/VERIFICATION.md: the A16 and tablet results of every phase test.
- Final check on a non-debuggable APK: install it through the file manager on the A16 and
  record the Play Protect result. A debug-key signature and "unknown developer" can still show a
  warning; Android developer verification for sideloaded apps is a separate topic.

## Order and dependencies

0 (switch) -> 1 (bash + apt, the early smoke test) -> 2 (desktop) -> 3 (jniLibs helpers) ->
4 (proot/Debian) -> 5 (glibc native) -> 7.

Phase 6 can start after 1 and must be finished before 7.

Every phase keeps the 28 build working. Before merging, run the phase's Phase 1 and Phase 2
tests on the tablet with `TARGET_SDK=28`.

## Main risks

1. linker64 exec of app-data files is tolerated, not guaranteed. A future Android release or a
   Play Protect heuristic can close it. Code that execs through raw syscalls or without our hook
   fails with EACCES regardless: Go, static binaries, some sandboxed launchers.
2. glibc pinning: the shipped libld.so/libc pair is decoupled from Debian's libc6 updates. The
   fallback is the userland-exec stub (Phase 5).
3. SELinux restrictions of newer untrusted_app domains beyond exec: netlink/getifaddrs (30+),
   /proc/net (29+), and ashmem for MIT-SHM and PulseAudio. Edge-to-edge and IME layout
   regressions also only show on the device.

## Review by Codex (2026-11-11) and changes to the plan

1. [blocker] The probe never set LD_PRELOAD: first prove, in the app process of a
   non-debuggable targetSdk 36 APK (not `run-as`, whose SELinux and seccomp differ), that
   linker64 loads an app-data preload and that a hooked child can start a grandchild. This is
   now step 1 of Phase 0 (exec-probe run as instrumentation, works on a locked phone).
2. Identity: `/proc/self/exe` may be the APEX linker path (`/apex/com.android.runtime/bin/linker64`),
   so canonicalise the linker identity; initialise identity lazily inside the wrappers
   (constructor order across libraries cannot be relied on); comm is limited to 15 bytes.
   Define and document the supported identity semantics (no setuid/capability exec).
3. AT_EXECFN, auxv and external `/proc/PID/exe` readers stay "linker64"; probe them.
4. Spawn: bionic may use vfork internally, so prepare the rewritten argv before calling libc;
   no allocation or dlsym in a vfork child. Test relative paths with spawn chdir actions,
   CLOEXEC fds for fexecve, PATH error precedence and the ENOEXEC shell fallback.
5. `env -i` children lose LD_PRELOAD and their descendants fail: define which variables are
   always propagated (LD_PRELOAD, DROIDDESK_*), also through droiddesk-glibc-native's `env -i`.
6. termux-exec: compare our hook against a pinned, app-controlled termux-exec build with
   differential tests before deciding finally; keep one interposer.
7. The 128-byte argv[0] limit applies to old Android only: drop the short-symlink workaround,
   keep long-path regression tests.
8. Phase 5: pinning preferred, but pin the gconv modules too and audit actual loads; the
   quick-exit fallback to proot covers GUI launches only (launcher line ~745).
9. [blocker] virgl must keep its clean environment (hook breaks vendor namespaces,
   LinuxRuntime ~3783): NativeExec separates command rewriting from environment policy.
10. Phase 1 is split: extraction -> linker64 bash -> one hooked child -> PTY login; apt and
    maintainer scripts after that. Terminal insets go with the PTY test, specialUse before
    desktop endurance tests.
11. Phase 6 corrections: at targetSdk 36 KEYCODE_BACK is no longer dispatched
    (TouchInputHandler relies on it): add an OnBackInvokedCallback; catch FGS start failures in
    MainActivity (~883) too; microphone FGS promotion can throw SecurityException; add a
    phantom-process endurance test (Android 12+), specialUse does not protect child processes.

Also found on the A16 (2026-11-11, targetSdk 28 build): the first setup stalls when the screen
turns off and the phone locks (proot tracees stopped, no foreground service during setup). The
setup needs a foreground service and a wake lock, independent of the targetSdk work.

## Probe result: preload under linker64 (Galaxy A16, Android 16, 2026-11-11)

exec-probe as instrumentation (`am instrument -w com.vyvrnc.execprobe/.ProbeInstrumentation`),
non-debuggable APK, targetSdk 36, domain `u:r:untrusted_app:s0` (not `_27`), phone locked:
- direct exec of an app-data file: EACCES (A, F); a spawned data child without a hook: 127 (H);
- bionic program via `/system/bin/linker64`: works (E); glibc via `libld.so`: works, also a
  glibc child (C, D);
- an LD_PRELOAD library from app data loads under linker64, its constructor gets the shifted
  argc/argv (I);
- the hook's posix_spawn and execve rewrites to linker64 work (J, K), also for grandchildren (L)
  and when the preload sits in `/system/bin/sh` (M); a preload from nativeLibraryDir works too (N).
- Identity under linker64 without a fix: argv[0] = the program path (the original argv[0] is
  lost), `/proc/self/exe` = `/apex/com.android.runtime/bin/linker64`, comm = `linker64`,
  AT_EXECFN = `/system/bin/linker64`.

The blocker from the review (finding 1) is cleared; the identity work of Phase 1 is needed.

## Progress (night 2026-11-11/12, branch `lexona-sdk36`, Galaxy A16)

Done and tested with `TARGET_SDK=36 tools/build-apk.sh` (non-debuggable, adb install, phone
locked, `am instrument … SmokeInstrumentation`):
- Phase 0: `-P lexona.targetSdk`, build-apk.sh `TARGET_SDK`, SmokeInstrumentation.
- Phase 1a/1b: socket_hook.c linker64 exec plan (ELF, `#!` chains, maintainer scripts),
  execl*/fexecve/posix_spawn(p)/PATH search, identity (argv[0], comm, readlink of
  /proc/self/exe); NativeExec.kt at all 21 LinuxRuntime exec sites and the terminal session.
  Result: bootstrap extracts, bash 5.3 runs as `bash` (comm), children and `/system/bin/sh`
  children work; `apt-get update` and `apt-get install nano` (download, unpack, configure,
  maintainer scripts) work; `dpkg --audit` clean.
- jniLibs `libproot-loader.so` replaced by the loader of Termux proot 5.1.107.102.

Open:
- proot at 36: `proot -0 /system/bin/id` fails with EPERM while translating execve (before the
  loader is used), also with PROOT_NO_SECCOMP=1 and with the loader from nativeLibraryDir;
  ptrace itself works (strace runs). Cause under investigation.
- Not tested yet (needs the screen unlocked): the in-app terminal (PTY login), the desktop.

## Lessons from Local Desktop (localdesktop/localdesktop 43082a8, GPLv3, targetSdk 36)

Read in source on 2026-11-12. It runs everything inside proot (Arch, glibc guest), so it needs
no exec hook; what is worth taking:
- proot fork (termux/proot ab2e346 + green-green-avk build scripts, talloc linked statically,
  loader as lib*.so, started directly from nativeLibraryDir with only PROOT_LOADER and
  PROOT_TMP_DIR). Their proot patches:
  - seccomp traps only the ioctls proot rewrites (TCSETS*/TCGETS2/FICLONE); without it Turnip
    on KGSL stops at the tracer on every GPU submit (relevant for Adreno under proot);
  - chmod on app-owned bound dirs under fake root;
  - fstat on sockets/pipes under fake root (Node/Electron children aborted without it).
- No foreground service and no phantom-process handling in code: their guide asks users to
  disable "child process restrictions" (Samsung developer option) or set
  `max_phantom_processes` over adb. We need the endurance test from the review (finding 11).
- Their libproot.so/libproot_loader.so are 4 KB aligned (may fail on 16 KB page kernels); link
  ours with `-z max-page-size=16384` when we build proot.
- Host-side PipeWire with an AAudio sink, fake /proc files, fake bwrap, Chromium --no-sandbox
  wrappers: ideas for later.
