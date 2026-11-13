# Plan: Shizuku tools for Linux (night run 2026-11-13)

Goal: the roadmap's Shizuku features, end to end on the Galaxy A16. No release.

## Design
- `ShellBridge` (app): abstract socket `lexona.shell`, same uid only. One JSON line per
  request, a JSON header back, then a raw stream ended by `\0LEXONA-EXIT:<n>\n`.
- Each op behind its own switch (SharedPreferences `lexona_shell`), all off by default,
  switched in Advanced:
  - `apk`: `install` (APK fds over SCM_RIGHTS, `pm install-create/write/commit`, splits and .apks/.xapk)
  - `logcat`: `logcat` (args, streamed; ends when the client goes away)
  - `screen`: `screencap` (PNG), `input`
  - `adb`: `exec` (one command) and `pty` (interactive shell: pty master from the shell-side
    UserService via termux JNI, passed on over SCM_RIGHTS)
- Battery: one tap (deviceidle whitelist + appops RUN_ANY_IN_BACKGROUND), app side only.
- Linux: one client `lexona-shizuku.py`, commands lexona-apk-install, lexona-logcat,
  lexona-screenshot, lexona-input, lexona-adb (Termux bin and Debian /usr/local/bin).
  Thunar/desktop: "Install on Android" for .apk files (default handler).

## Steps
1. ShellBridge + AIDL openShell + ShizukuSupport battery
2. MainActivity channel + Dart bridge + Advanced UI
3. Linux client + LinuxRuntime install + .desktop
4. Build, install on A16, e2e each op (switch off -> refused, on -> works)
5. Docs (VERIFICATION, backlog), commit, push 3 branches. No release.

## Status
(updated as steps finish)
