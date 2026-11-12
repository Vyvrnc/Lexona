#!/bin/bash
# Lexona lifecycle checks from a computer over adb, with the desktop running on the device:
#   ADB=/path/to/adb DEV=host:port bash tools/device-test/lifecycle.sh
# Screen off/on, app in the background, rotation, Android app launch from Linux, notification,
# Restart desktop, Stop server, force-stop and a new start. Prints PASS/FAIL per check.
set -u
ADB=${ADB:-adb}; DEV=${DEV:?set DEV=host:port}; PKG=io.github.vyvrnc.lexona
a() { MSYS_NO_PATHCONV=1 "$ADB" -s "$DEV" "$@"; }
res() { echo "$1 $2${3:+ ($3)}"; }
pid_of() { a shell "ps -A -o PID,NAME" | awk -v n="$1" '$2==n{print $1; exit}'; }
uid=$(a shell "ps -A -o USER,NAME" | awk -v p="$PKG" '$2==p{print $1; exit}')
focus() { a shell dumpsys window | grep -m1 mCurrentFocus; }
[ -n "$(pid_of xfdesktop)" ] || { echo "start the desktop first"; exit 2; }
session=$(pid_of xfce4-session)

# Screen off for 60 s, then on: same session. Only with SCREEN_OFF=1: on a phone with a PIN the
# lock screen stays after it and every later check that needs the screen is blocked.
if [ "${SCREEN_OFF:-0}" = 1 ]; then
    a shell input keyevent KEYCODE_SLEEP; sleep 60; a shell input keyevent KEYCODE_WAKEUP; sleep 3
    [ "$(pid_of xfce4-session)" = "$session" ] && res PASS "screen off 60 s keeps the session" || res FAIL "screen off 60 s" "session pid changed"
    a shell wm dismiss-keyguard >/dev/null 2>&1
else res SKIP "screen off 60 s" "SCREEN_OFF=1 to run it (locks a phone with a PIN)"; fi

# App in the background (Home) for 120 s.
a shell input keyevent KEYCODE_HOME; sleep 120
[ "$(pid_of xfce4-session)" = "$session" ] && res PASS "app in the background 120 s keeps the session" || res FAIL "background 120 s" "session pid changed"
a shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 5

# Foreground service notification.
a shell dumpsys notification --noredact | grep -q "pkg=$PKG" && res PASS "session notification shown" || res FAIL "session notification"

# Rotation: landscape and back (accelerometer off for the test, restored after).
acc=$(a shell settings get system accelerometer_rotation); rot=$(a shell settings get system user_rotation)
a shell settings put system accelerometer_rotation 0; a shell settings put system user_rotation 1; sleep 6
a shell exec-out screencap -p > /tmp/lx-rot.png 2>/dev/null
[ "$(pid_of xfce4-session)" = "$session" ] && res PASS "rotation to landscape keeps the session" || res FAIL "rotation" "session pid changed"
a shell settings put system user_rotation "${rot/null/0}"; a shell settings put system accelerometer_rotation "${acc/null/1}"; sleep 4

# Android app from Linux: lexona-open --android URL opens an Android browser.
echo "(launch from Linux is checked in full.sh's terminal run; here only the bridge socket)"
a shell "cat /proc/net/unix" | grep -q "@lexona.android-app-launcher" && res PASS "Android app launcher bridge listening" || res FAIL "launcher bridge" "socket missing"
a shell "cat /proc/net/unix" | grep -q "@droiddesk\." && res FAIL "no droiddesk.* sockets left" "found some" || res PASS "no droiddesk.* sockets (coexists with DroidDesk)"

# Force-stop the app, start again, launch the desktop: it comes back (stale agents do not block).
a shell am force-stop "$PKG"; sleep 3
left=$(a shell "ps -A -o USER,NAME" | awk -v u="$uid" '$1==u{print $2}' | tr '\n' ' ')
res INFO "left after force-stop: ${left:-nothing}"
echo "Now launch the desktop on the device (or the caller taps), then rerun the first check."
