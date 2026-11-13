#!/usr/bin/env python3
"""Android shell rights for Linux through Shizuku (Lexona -> Advanced).

  lexona-apk-install [--gui] APP.apk [SPLIT.apk ...] | BUNDLE.apks|.xapk|.apkm
                          install on the phone, without asking (switch "Install apps")
  lexona-logcat [ARGS]    Android's log, as adb logcat (switch "Android logs")
  lexona-screenshot [FILE.png]
                          the phone's screen as PNG (default ~/Pictures/android-<time>.png)
  lexona-input ARGS       taps, swipes, keys and text, as adb shell input (switch "Screen and input")
  lexona-adb [COMMAND]    shell as the adb user; with COMMAND only that (switch "Full Android shell")

Each group has its own switch in Lexona -> Advanced, all off until you turn them on.
"""
import json
import os
import select
import signal
import socket
import struct
import sys
import tempfile
import time
import zipfile

SOCKET = "\0lexona.shell"
MARK = b"\0LEXONA-EXIT:"
SWITCH_NAMES = {
    "apk": "Install apps from Linux",
    "logcat": "Android logs",
    "screen": "Screen and input",
    "adb": "Full Android shell",
}


class Refused(Exception):
    pass


def explain(error):
    if error.startswith("switch:"):
        name = SWITCH_NAMES.get(error[7:], error[7:])
        return 'turned off: Lexona -> Advanced -> "%s"' % name
    if error.startswith("shizuku:"):
        state = error[8:]
        if state in ("granted", "service"):
            return "Shizuku could not start Lexona's shell service (see logcat)"
        return "Shizuku is %s: start it and allow Lexona (Lexona -> Advanced)" % state
    return error


def connect(request, fds=()):
    """Sends the request; returns (socket, header dict)."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(SOCKET)
    except OSError as error:
        raise Refused("Lexona's shell bridge is not running (%s): open the Lexona desktop or terminal" % error)
    data = (json.dumps(request) + "\n").encode()
    if fds:
        socket.send_fds(sock, [data], list(fds))
    else:
        sock.sendall(data)
    return sock


def read_header(sock, want_fd=False):
    data, fd = b"", None
    while not data.endswith(b"\n"):
        if want_fd and fd is None:
            msg, fds, _flags, _addr = socket.recv_fds(sock, 1, 4)
            if fds:
                fd = fds[0]
                for extra in fds[1:]:
                    os.close(extra)
        else:
            msg = sock.recv(1)
        if not msg:
            break
        data += msg
    header = json.loads(data.decode() or '{"ok": false, "error": "no answer from Lexona"}')
    if not header.get("ok"):
        if fd is not None:
            os.close(fd)
        raise Refused(explain(header.get("error", "refused")))
    return header, fd


def maybe_mark(tail):
    """True when tail (starting with NUL) is the exit mark or may become it."""
    if len(tail) <= len(MARK):
        return MARK.startswith(tail)
    if not tail.startswith(MARK):
        return False
    rest = tail[len(MARK):]
    if rest.endswith(b"\n"):
        rest = rest[:-1]
    return rest == b"" or rest.isdigit()


def stream(sock, out):
    """Copies the output to out (binary) until the exit mark; returns the exit status."""
    pending = b""
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        pending += chunk
        # Hold back only what may be the start of the exit mark (from the last NUL on).
        i = pending.rfind(b"\0")
        if i < 0 or not maybe_mark(pending[i:]):
            i = len(pending)
        if i > 0:
            out.write(pending[:i])
            out.flush()
            pending = pending[i:]
    i = pending.rfind(MARK)
    if i < 0:
        out.write(pending)
        out.flush()
        return 255  # cut off: the app went away
    out.write(pending[:i])
    out.flush()
    try:
        return int(pending[i + len(MARK):].strip() or b"0")
    except ValueError:
        return 255


def run_streamed(request, out=None, stdin=False):
    """stdin True: our input (fd 0) goes to the command until it ends. Otherwise the socket's
    write side stays open: when we go away (Ctrl-C), the app ends the command."""
    request["stdin"] = bool(stdin)
    sock = connect(request)
    read_header(sock)
    if stdin:
        import threading

        def feed():
            try:
                while True:
                    block = os.read(0, 65536)
                    if not block:
                        break
                    sock.sendall(block)
            except OSError:
                pass
            try:
                sock.shutdown(socket.SHUT_WR)
            except OSError:
                pass

        threading.Thread(target=feed, daemon=True).start()
    try:
        return stream(sock, out or sys.stdout.buffer)
    finally:
        sock.close()


# --- lexona-apk-install ------------------------------------------------------------------

def apk_files(paths, tmp):
    """APK paths; bundles (.apks, .xapk, .apkm: zips of APKs) unpacked into tmp."""
    result = []
    for path in paths:
        if not os.path.isfile(path):
            raise Refused("%s: no such file" % path)
        with open(path, "rb") as f:
            magic = f.read(4)
        if magic[:2] != b"PK":
            raise Refused("%s: not an APK" % path)
        with zipfile.ZipFile(path) as z:
            names = z.namelist()
            if "AndroidManifest.xml" in names:
                result.append(path)
                continue
            inner = [n for n in names if n.lower().endswith(".apk")]
            # bundletool: splits/ holds the real set, standalones/ alternatives for old Androids.
            if any(n.startswith("splits/") for n in inner):
                inner = [n for n in inner if not n.startswith("standalones/")]
            if not inner:
                raise Refused("%s: neither an APK nor a bundle of APKs" % path)
            for k, n in enumerate(inner):
                target = os.path.join(tmp, "%d-%s" % (len(result) + k, os.path.basename(n)))
                with z.open(n) as src, open(target, "wb") as dst:
                    while True:
                        block = src.read(1 << 20)
                        if not block:
                            break
                        dst.write(block)
                result.append(target)
    return result


def apk_install(args):
    gui = False
    if args and args[0] == "--gui":
        gui, args = True, args[1:]
    if not args or args[0] in ("-h", "--help"):
        print("usage: lexona-apk-install [--gui] APP.apk [SPLIT.apk ...] | BUNDLE.apks|.xapk|.apkm")
        return 0 if args else 2
    title = os.path.basename(args[0])
    try:
        with tempfile.TemporaryDirectory(prefix="lexona-apk-") as tmp:
            files = apk_files(args, tmp)
            handles = [open(p, "rb") for p in files]
            try:
                names = [os.path.basename(p) for p in files]
                sock = connect({"op": "install", "names": names}, [h.fileno() for h in handles])
                read_header(sock)

                class Collect:
                    data = b""

                    def write(self, b):
                        self.data += b
                        if not gui:
                            sys.stdout.buffer.write(b)

                    def flush(self):
                        if not gui:
                            sys.stdout.buffer.flush()

                collect = Collect()
                status = stream(sock, collect)
                sock.close()
            finally:
                for h in handles:
                    h.close()
        text = collect.data.decode(errors="replace").strip()
    except Refused as error:
        status, text = 1, str(error)
        if not gui:
            print("lexona-apk-install: " + text, file=sys.stderr)
    if gui:
        notify(title, status, text)
    return status


def notify(title, status, text):
    """Result for "Install on Android" in the file manager: a notification, else a dialog."""
    import shutil
    import subprocess
    last = text.splitlines()[-1] if text else ""
    summary = ("Installed on Android: " if status == 0 else "Not installed: ") + title
    body = "" if status == 0 else last
    if shutil.which("notify-send"):
        if subprocess.call(["notify-send", "-i", "android" if status == 0 else "dialog-error", summary, body]) == 0:
            return
    for dialog in (["zenity", "--info" if status == 0 else "--error", "--text", summary + "\n" + body],
                   ["xmessage", "-center", summary + "\n" + body]):
        if shutil.which(dialog[0]):
            subprocess.call(dialog)
            return


# --- lexona-screenshot -------------------------------------------------------------------

def screenshot(args):
    if args and args[0] in ("-h", "--help"):
        print("usage: lexona-screenshot [FILE.png | -]")
        return 0
    target = args[0] if args else None
    if target == "-":
        return run_streamed({"op": "screencap"})
    if target is None:
        folder = os.path.expanduser("~/Pictures")
        os.makedirs(folder, exist_ok=True)
        target = os.path.join(folder, time.strftime("android-%Y%m%d-%H%M%S.png"))
    partial = target + ".part"
    try:
        with open(partial, "wb") as out:
            status = run_streamed({"op": "screencap"}, out)
    except Refused:
        os.unlink(partial)
        raise
    with open(partial, "rb") as f:
        good = f.read(8) == b"\x89PNG\r\n\x1a\n"
    if status != 0 or not good:
        os.unlink(partial)
        print("lexona-screenshot: no picture (status %d)" % status, file=sys.stderr)
        return status or 1
    os.replace(partial, target)
    print(target)
    return 0


# --- lexona-adb ----------------------------------------------------------------------------

def write_all(fd, data):
    while data:
        data = data[os.write(fd, data):]


def interactive_shell():
    import termios
    import tty
    import fcntl
    rows, cols = 24, 80
    if os.isatty(1):
        size = fcntl.ioctl(1, termios.TIOCGWINSZ, b"\0" * 8)
        rows, cols = struct.unpack("HHHH", size)[:2]
    env = ["%s=%s" % (k, os.environ[k]) for k in ("TERM", "COLORTERM", "LANG") if k in os.environ]
    sock = connect({"op": "pty", "rows": rows, "cols": cols, "env": env})
    _header, master = read_header(sock, want_fd=True)
    sock.close()
    if master is None:
        raise Refused("no terminal from Lexona")

    def resize(*_):
        try:
            size = fcntl.ioctl(1, termios.TIOCGWINSZ, b"\0" * 8)
            fcntl.ioctl(master, termios.TIOCSWINSZ, size)
        except OSError:
            pass

    signal.signal(signal.SIGWINCH, resize)
    saved = termios.tcgetattr(0) if os.isatty(0) else None
    try:
        if saved:
            tty.setraw(0)
        while True:
            try:
                ready, _, _ = select.select([0, master], [], [])
            except InterruptedError:
                continue
            if master in ready:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    data = b""
                if not data:
                    break
                write_all(1, data)
            if 0 in ready:
                data = os.read(0, 65536)
                if not data:
                    break
                write_all(master, data)
    finally:
        if saved:
            termios.tcsetattr(0, termios.TCSADRAIN, saved)
        os.close(master)
    return 0


def adb(args):
    if args and args[0] in ("-h", "--help"):
        print("usage: lexona-adb [COMMAND [ARGS...]]   (as adb shell; no COMMAND: interactive shell)")
        return 0
    if args and args[0] == "shell":  # "lexona-adb shell ls" as typed for adb
        args = args[1:]
    if not args:
        if not os.isatty(0):
            return run_streamed({"op": "exec", "args": ["sh"]}, stdin=True)
        return interactive_shell()
    return run_streamed({"op": "exec", "args": args}, stdin=not os.isatty(0))


def main():
    name = os.path.basename(sys.argv[0])
    if name.endswith(".py"):
        name = name[:-3]
    args = sys.argv[1:]
    if name in ("lexona-shizuku",) and args:
        name, args = "lexona-" + args[0], args[1:]
    try:
        if name == "lexona-apk-install":
            return apk_install(args)
        if name == "lexona-logcat":
            return run_streamed({"op": "logcat", "args": args})
        if name == "lexona-screenshot":
            return screenshot(args)
        if name == "lexona-input":
            if not args or args[0] in ("-h", "--help"):
                print("usage: lexona-input tap X Y | swipe X1 Y1 X2 Y2 [MS] | text TEXT | keyevent KEY ...")
                return 0 if args else 2
            return run_streamed({"op": "input", "args": args})
        if name == "lexona-adb":
            return adb(args)
        print(__doc__.strip())
        return 2
    except Refused as error:
        print("%s: %s" % (name, error), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    except BrokenPipeError:
        return 141


if __name__ == "__main__":
    code = main()
    try:
        sys.stdout.flush()
    except OSError:
        pass
    # No interpreter shutdown: a stdin feeder thread may still sit in a read.
    os._exit(code)
