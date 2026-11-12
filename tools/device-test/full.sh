#!/bin/bash
# Lexona functional test, run in the app's terminal with the desktop running:
#   bash full.sh [--heavy]      (--heavy also installs clang and Debian python3/mesa-utils)
# One line per check: PASS / FAIL (a bug) / LIMIT (expected limit of targetSdk >= 29) / SKIP.
# Report: /sdcard/Download/lexona-test/report.txt (needs All files access), also on stdout.
set -u
HEAVY=0; [ "${1:-}" = --heavy ] && HEAVY=1
out=/sdcard/Download/lexona-test; mkdir -p "$out" 2>/dev/null || out=$TMPDIR
report=$out/report.txt; : > "$report"
w=$(mktemp -d "$TMPDIR/lxtest.XXXXXX")
export DISPLAY=:0
log() { echo "$*" | tee -a "$report"; }
res() { log "$1 $2${3:+ ($3)}"; }
# chk NAME CMD...: PASS when CMD exits 0, else FAIL with the last output line.
chk() { local n=$1; shift; local o; if o=$("$@" 2>&1); then res PASS "$n"; else res FAIL "$n" "$(printf %s "$o" | tail -1 | cut -c1-90)"; fi; }
# lim NAME CMD...: CMD is expected to fail at targetSdk >= 29 (LIMIT), PASS if it works anyway.
lim() { local n=$1; shift; local o; if o=$("$@" 2>&1); then res PASS "$n"; else res LIMIT "$n" "$(printf %s "$o" | tail -1 | cut -c1-90)"; fi; }
ms() { local t0 t1; t0=$(date +%s%N); "$@" >/dev/null 2>&1; t1=$(date +%s%N); echo $(( (t1 - t0) / 1000000 )); }
R=$PREFIX/var/lib/proot-distro/containers/debian/rootfs
log "== Lexona functional test $(date '+%F %T'), targetSdk $(getprop ro.build.version.sdk) device $(getprop ro.product.model)"

log "== exec model"
chk "bash identity (comm, argv0)" bash -c 'test "$(cat /proc/$$/comm)" = bash'
printf '#!/usr/bin/env python3\nprint("ok")\n' > "$w/s.py"; chmod +x "$w/s.py"
chk "script with #!/usr/bin/env shebang" bash -c "test \"\$($w/s.py)\" = ok"
chk "python subprocess" python3 -c 'import subprocess;assert subprocess.run(["uname","-m"],capture_output=True).returncode==0'
chk "python fork + execv" python3 -c 'import os,shutil;p=os.fork()
if p==0: os.execv(shutil.which("true"),["true"])
assert os.waitpid(p,0)[1]==0'
chk "python /proc/self/exe" python3 -c 'import os,sys;assert os.readlink("/proc/self/exe").endswith("python3.14") or "python3" in os.readlink("/proc/self/exe")'
chk "pipes, xargs, find -exec" bash -c 'ls / | xargs -n1 echo >/dev/null && find "$PREFIX/bin" -maxdepth 1 -name ls -exec {} / \; >/dev/null'
lim "child after env -i (loses the hook)" env -i PATH="$PATH" bash -c 'ls / >/dev/null'
cp "$DROIDDESK_NATIVE_LIB_DIR/libdroiddesk_eth.so" "$w/static-bin"; chmod +x "$w/static-bin"
chk "static ELF in app data (through proot)" bash -c "\"$w/static-bin\" help 2>&1 | grep -qi eth"
a=$(ms bash -c 'for i in $(seq 200); do "$PREFIX/bin/true"; done'); b=$(ms bash -c 'for i in $(seq 200); do /system/bin/true; done')
log "INFO exec of 200 programs: app data (linker64) ${a} ms, /system/bin ${b} ms"

log "== Termux packages and tools"
chk "pkg install (tree, xdotool, gh)" pkg install -y tree xdotool gh
chk "tree runs" tree -L 1 "$PREFIX"
chk "git clone https" git clone -q --depth 1 https://github.com/octocat/Hello-World "$w/hw"
chk "ssh-keygen" ssh-keygen -q -t ed25519 -N '' -f "$w/k"
chk "pip install (pure)" python3 -m pip install -q --target "$w/pip" six
gh alias set lxtest '!echo hi' --shell >/dev/null 2>&1
chk "Go program spawning a program (gh alias, through proot)" bash -c 'test "$(gh lxtest 2>&1)" = hi'
gh alias delete lxtest >/dev/null 2>&1
if [ $HEAVY = 1 ]; then
    chk "pkg install clang" pkg install -y clang
    printf '#include <stdio.h>\nint main(void){puts("built");return 0;}\n' > "$w/h.c"
    chk "compile and run a C program in \$HOME" bash -c "clang -o $w/h $w/h.c && test \"\$($w/h)\" = built"
fi

log "== Debian"
chk "debian-run (native glibc)" bash -c 'debian-run /usr/bin/env | grep -q DD_NATIVE_ACTIVE=1'
chk "glibc program -> Termux program" bash -c "debian-run /usr/bin/bash -c '$PREFIX/bin/uname -m' | grep -q aarch64"
chk "debian-run through proot" bash -c 'DD_NATIVE=0 debian-run cat /etc/debian_version | grep -q "^1[0-9]"'
chk "apt install in Debian (hello)" bash -c 'debian-run apt-get install -y -q hello >/dev/null && debian-run hello | grep -q Hello'
a=$(ms debian-run /usr/bin/true); b=$(ms env DD_NATIVE=0 debian-run /usr/bin/true)
log "INFO debian-run true: native ${a} ms, proot ${b} ms"
if [ $HEAVY = 1 ]; then
    chk "Debian python3 (apt, native run)" bash -c 'debian-run apt-get install -y -q python3 >/dev/null && debian-run python3 -c "import ssl,json;print(1)" | grep -q 1'
    chk "Debian OpenGL with lexona-gpu (virgl)" bash -c 'debian-run apt-get install -y -q mesa-utils >/dev/null && debian-run bash -lc "lexona-gpu on >/dev/null; timeout 8 gpu-run glxgears" 2>&1 | grep -q FPS'
fi
if debian-run bash -lc 'command -v claude' >/dev/null 2>&1; then
    chk "Claude Code native" bash -c "debian-run bash -lc 'claude --version' | grep -q 'Claude Code'"
else res SKIP "Claude Code native" "not installed (Add applications)"; fi

log "== desktop"
chk "XFCE processes" bash -c 'pgrep -x xfdesktop && pgrep -x xfce4-panel && pgrep -x xfwm4'
for app in xfce4-terminal thunar mousepad ristretto; do
    ( setsid "$app" >/dev/null 2>&1 & )
done
sleep 12
chk "xfce4-terminal window" xdotool search --onlyvisible --class xfce4-terminal
chk "Thunar window" xdotool search --onlyvisible --class thunar
chk "Mousepad window" xdotool search --onlyvisible --class mousepad
chk "Ristretto window" xdotool search --onlyvisible --class ristretto
chk "screenshot of the desktop" bash -c "xfce4-screenshooter -f -s $w/shot.png && test \$(stat -c %s $w/shot.png) -gt 20000"
cp "$w/shot.png" "$out/desktop.png" 2>/dev/null
for app in xfce4-terminal thunar mousepad ristretto; do pkill -x "$app"; done
chk "X clipboard (xclip)" bash -c 'echo lexona-clip | xclip -selection clipboard && test "$(xclip -o -selection clipboard)" = lexona-clip'
chk "Firefox headless page load" bash -c "timeout 90 firefox --headless --screenshot $w/ff.png https://example.org >/dev/null 2>&1; test -s $w/ff.png"

log "== Android integration"
chk "storage: write and read Download" bash -c "echo x > ~/storage/downloads/.lexona-test && grep -q x ~/storage/downloads/.lexona-test && rm ~/storage/downloads/.lexona-test"
python3 -c 'import wave,struct,math;f=wave.open("'"$w"'/t.wav","w");f.setnchannels(1);f.setsampwidth(2);f.setframerate(44100);f.writeframes(b"".join(struct.pack("<h",int(3000*math.sin(i/10))) for i in range(44100)));f.close()'
chk "audio playback (paplay 1 s)" timeout 10 paplay "$w/t.wav"
chk "network bridge (lexona-net)" timeout 10 lexona-net status
chk "DNS and HTTPS" bash -c 'python3 -c "import socket;socket.gethostbyname(\"github.com\")" && curl -sI --max-time 10 https://github.com | head -1 | grep -q 200'
chk "USB bridge reachable (lexona-usb list)" timeout 10 lexona-usb list
chk "serial bridge reachable" timeout 10 lexona-serial list
chk "droiddesk-eth from the APK" bash -c 'out=$(timeout 10 droiddesk-eth status 2>&1); echo "$out"; ! echo "$out" | grep -qi "neběží (chybí USB most\|permission denied\|exec format"'
chk "camera bridge reachable" bash -c 'out=$(timeout 10 lexona-camera status 2>&1); echo "$out"; ! echo "$out" | grep -qi "connection refused\|no such file"'

rm -rf "$w"
log "== done $(date +%T)"
