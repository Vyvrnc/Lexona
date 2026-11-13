#!/usr/bin/env python3
"""lexona-android-data: Android/data and Android/obb in Linux, over WebDAV (Thunar, gio).

  lexona-android-data            start (or show the running one) and print its URL
  lexona-android-data --stop     stop it

Needs Shizuku with Lexona allowed (Process limit or Android data in the app). The app's
shell-side service opens the files and hands their descriptors over the abstract socket
"lexona.android-data"; this server reads and writes them itself.

Listens on 127.0.0.1 only, and every app on the phone can reach 127.0.0.1: the files sit
below a random path (dav://localhost:PORT/SECRET/), refused for other Host and Origin headers.
The URL is also added to Thunar's side panel (GTK bookmarks) as "Android data".
State: $TMPDIR/lexona-android-data.json, log: $TMPDIR/lexona-android-data.log.
"""
import array
import email.utils
import json
import mimetypes
import os
import secrets
import signal
import socket
import sys
import threading
import urllib.parse
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.sax.saxutils import escape

SOCKET = "\0lexona.android-data"
ROOTS = {"data": "/storage/emulated/0/Android/data", "obb": "/storage/emulated/0/Android/obb"}
ALLOWED_HOSTS = {"localhost", "127.0.0.1", "::1"}
TMP = os.environ.get("TMPDIR", "/tmp")
STATE = os.path.join(TMP, "lexona-android-data.json")
LOG = os.path.join(TMP, "lexona-android-data.log")
CHUNK = 1 << 20


class Failure(Exception):
    def __init__(self, status, text=""):
        super().__init__(text)
        self.status, self.text = status, text


def ask(request, want_fd=False):
    """One request to the app; (reply dict, fd or None)."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(SOCKET)
    except OSError as error:
        raise Failure(503, "Lexona's Android data bridge is not running: open Lexona once (%s)" % error)
    try:
        sock.sendall((json.dumps(request) + "\n").encode())
        data, fd = b"", None
        while not data.endswith(b"\n"):
            if want_fd and fd is None:
                msg, fds, _flags, _addr = socket.recv_fds(sock, 65536, 1)
                if fds:
                    fd = fds[0]
            else:
                msg = sock.recv(65536)
            if not msg:
                break
            data += msg
        reply = json.loads(data.decode() or "{}")
    finally:
        sock.close()
    err = reply.get("error", "")
    if err.startswith("shizuku:"):
        if fd is not None:
            os.close(fd)
        state = err[8:]
        if state == "granted":
            raise Failure(503, "Shizuku could not start Lexona's file service (see logcat)")
        raise Failure(503, "Shizuku is " + state + ": start it and allow Lexona")
    return reply, fd


def android_path(path):
    """"/data/com.x/files" -> "/storage/emulated/0/Android/data/com.x/files"; "/" -> None."""
    parts = [p for p in path.split("/") if p]
    if not parts:
        return None
    if parts[0] not in ROOTS or any(p in ("..", ".") for p in parts):
        raise Failure(404)
    return "/".join([ROOTS[parts[0]]] + parts[1:])


def stat(path):
    """(is_dir, size, mtime_ms) or None."""
    real = android_path(path)
    if real is None or (path.strip("/") in ROOTS and "/" not in path.strip("/")):
        return (True, 0, 0)
    reply, _ = ask({"op": "stat", "path": real})
    if not reply.get("ok"):
        return None
    kind, size, mtime = reply["stat"].split("\t")
    return (kind == "d", int(size), int(mtime))


def listing(path):
    """[(name, is_dir, size, mtime_ms)]."""
    real = android_path(path)
    if real is None:
        return [(name, True, 0, 0) for name in ROOTS]
    reply, _ = ask({"op": "list", "path": real})
    if not reply.get("ok"):
        raise Failure(404)
    out = []
    for line in reply["entries"].split("\n"):
        if line:
            kind, size, mtime, name = line.split("\t", 3)
            out.append((name, kind == "d", int(size), int(mtime)))
    return out


def open_fd(path, mode):
    reply, fd = ask({"op": "open", "path": android_path(path), "mode": mode}, want_fd=True)
    if not reply.get("ok") or fd is None:
        raise Failure(403 if mode != "r" else 404)
    return fd


SECRET = ""


def normalize(raw):
    path = urllib.parse.unquote(urllib.parse.urlsplit(raw).path, errors="strict")
    prefix = "/" + SECRET
    if path != prefix and not path.startswith(prefix + "/"):
        raise Failure(404)
    path = path[len(prefix):]
    parts = [p for p in path.split("/") if p not in ("", ".")]
    if any(p == ".." or "\0" in p for p in parts):
        raise Failure(400)
    return "/" + "/".join(parts)


def href(path, is_dir):
    full = "/" + SECRET + (path if path != "/" else "/")
    if is_dir and not full.endswith("/"):
        full += "/"
    return urllib.parse.quote(full, safe="/")


def prop(path, is_dir, size, mtime):
    name = path.rstrip("/").rsplit("/", 1)[-1] or "Android"
    date = email.utils.formatdate(mtime / 1000, usegmt=True) if mtime else ""
    props = [f"<D:displayname>{escape(name)}</D:displayname>"]
    if date:
        props.append(f"<D:getlastmodified>{date}</D:getlastmodified>")
    if is_dir:
        props.append("<D:resourcetype><D:collection/></D:resourcetype>")
    else:
        props.append("<D:resourcetype/>")
        props.append(f"<D:getcontentlength>{size}</D:getcontentlength>")
        kind = mimetypes.guess_type(name)[0] or "application/octet-stream"
        props.append(f"<D:getcontenttype>{escape(kind)}</D:getcontenttype>")
    return (f"<D:response><D:href>{escape(href(path, is_dir))}</D:href><D:propstat><D:prop>"
            + "".join(props) + "</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "lexona-android-data"

    def log_message(self, fmt, *args):
        sys.stderr.write("lexona-android-data: %s\n" % (fmt % args))

    def send(self, status, body=b"", headers=(), content_type="text/plain; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for k, v in headers:
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def check(self):
        host = (self.headers.get("Host") or "").rsplit(":", 1)[0].strip("[]")
        if host not in ALLOWED_HOSTS or self.headers.get("Origin"):
            raise Failure(403, "only local WebDAV clients")

    def dispatch(self):
        try:
            self.check()
            getattr(self, "dav_" + self.command.lower())()
        except Failure as error:
            self.send(error.status, error.text)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as error:  # noqa: BLE001 - answered, logged
            self.log_message("%s", error)
            self.send(500, str(error))

    do_OPTIONS = do_PROPFIND = do_PROPPATCH = do_GET = do_HEAD = do_PUT = dispatch
    do_MKCOL = do_DELETE = do_MOVE = do_COPY = do_LOCK = do_UNLOCK = dispatch

    def dav_options(self):
        self.send(200, headers=[("DAV", "1, 2"), ("Allow", "OPTIONS, PROPFIND, PROPPATCH, GET, HEAD, PUT, "
                                                     "MKCOL, DELETE, MOVE, COPY, LOCK, UNLOCK")])

    def dav_propfind(self):
        self.body()
        path = normalize(self.path)
        st = stat(path)
        if st is None:
            raise Failure(404)
        out = [prop(path, *st)]
        if st[0] and self.headers.get("Depth", "1") != "0":
            for name, is_dir, size, mtime in listing(path):
                out.append(prop(path.rstrip("/") + "/" + name, is_dir, size, mtime))
        self.send(207, '<?xml version="1.0" encoding="utf-8"?>\n<D:multistatus xmlns:D="DAV:">'
                  + "".join(out) + "</D:multistatus>", content_type='application/xml; charset="utf-8"')

    def dav_proppatch(self):
        self.body()
        path = normalize(self.path)
        self.send(207, '<?xml version="1.0" encoding="utf-8"?>\n<D:multistatus xmlns:D="DAV:"><D:response>'
                  f"<D:href>{escape(href(path, False))}</D:href><D:propstat><D:prop/>"
                  "<D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>",
                  content_type='application/xml; charset="utf-8"')

    def dav_head(self):
        self.dav_get()

    def dav_get(self):
        path = normalize(self.path)
        st = stat(path)
        if st is None:
            raise Failure(404)
        if st[0]:
            names = "".join(f'<li><a href="{href(path.rstrip("/") + "/" + n, d)}">{escape(n)}</a></li>'
                            for n, d, _s, _m in listing(path))
            self.send(200, f"<ul>{names}</ul>", content_type="text/html; charset=utf-8")
            return
        size = st[1]
        start, end, status = 0, size - 1, 200
        rng = self.headers.get("Range", "")
        if rng.startswith("bytes=") and "," not in rng:
            a, _, b = rng[6:].partition("-")
            if a:
                start = int(a)
                end = int(b) if b else size - 1
            elif b:
                start = max(0, size - int(b))
            end = min(end, size - 1)
            if start > end:
                self.send(416, headers=[("Content-Range", f"bytes */{size}")])
                return
            status = 206
        fd = open_fd(path, "r")
        with os.fdopen(fd, "rb") as f:
            self.send_response(status)
            self.send_header("Content-Type", mimetypes.guess_type(path)[0] or "application/octet-stream")
            self.send_header("Content-Length", str(end - start + 1 if size else 0))
            self.send_header("Accept-Ranges", "bytes")
            if status == 206:
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.end_headers()
            if self.command == "HEAD" or not size:
                return
            f.seek(start)
            left = end - start + 1
            while left > 0:
                data = f.read(min(CHUNK, left))
                if not data:
                    break
                self.wfile.write(data)
                left -= len(data)

    def dav_put(self):
        path = normalize(self.path)
        if android_path(path) is None or path.count("/") < 2:
            raise Failure(403)
        existed = stat(path) is not None
        fd = open_fd(path, "w")
        left = int(self.headers.get("Content-Length") or 0)
        with os.fdopen(fd, "wb") as f:
            while left > 0:
                data = self.rfile.read(min(CHUNK, left))
                if not data:
                    break
                f.write(data)
                left -= len(data)
        self.send(204 if existed else 201)

    def dav_mkcol(self):
        self.body()
        path = normalize(self.path)
        reply, _ = ask({"op": "mkdir", "path": android_path(path)})
        self.send(201 if reply.get("ok") else 409)

    def dav_delete(self):
        path = normalize(self.path)
        reply, _ = ask({"op": "delete", "path": android_path(path), "recursive": True})
        self.send(204 if reply.get("ok") else 403)

    def destination(self):
        dest = self.headers.get("Destination")
        if not dest:
            raise Failure(400)
        return normalize(dest)

    def dav_move(self):
        src, dst = normalize(self.path), self.destination()
        reply, _ = ask({"op": "rename", "path": android_path(src), "to": android_path(dst)})
        self.send(201 if reply.get("ok") else 403)

    def dav_copy(self):
        src, dst = normalize(self.path), self.destination()
        st = stat(src)
        if st is None:
            raise Failure(404)
        if st[0]:
            raise Failure(501, "copying folders: copy their files")
        with os.fdopen(open_fd(src, "r"), "rb") as r, os.fdopen(open_fd(dst, "w"), "wb") as w:
            while True:
                data = r.read(CHUNK)
                if not data:
                    break
                w.write(data)
        self.send(201)

    def dav_lock(self):
        self.body()
        token = "opaquelocktoken:" + str(uuid.uuid4())
        xml = ('<?xml version="1.0" encoding="utf-8"?>\n<D:prop xmlns:D="DAV:"><D:lockdiscovery><D:activelock>'
               "<D:locktype><D:write/></D:locktype><D:lockscope><D:exclusive/></D:lockscope>"
               "<D:depth>0</D:depth><D:timeout>Second-3600</D:timeout>"
               f"<D:locktoken><D:href>{token}</D:href></D:locktoken></D:activelock></D:lockdiscovery></D:prop>")
        self.send(200, xml, headers=[("Lock-Token", f"<{token}>")], content_type='application/xml; charset="utf-8"')

    def dav_unlock(self):
        self.send(204)


def running():
    try:
        with open(STATE, encoding="utf-8") as f:
            state = json.load(f)
        os.kill(state["pid"], 0)
        return state
    except (OSError, ValueError, KeyError):
        return None


def bookmark(url):
    """Thunar's side panel: a GTK bookmark "Android data"."""
    path = os.path.expanduser("~/.config/gtk-3.0/bookmarks")
    try:
        lines = open(path, encoding="utf-8").read().splitlines() if os.path.exists(path) else []
        lines = [line for line in lines if not line.endswith(" Android data")]
        lines.append(url + " Android data")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    except OSError:
        pass


def main():
    global SECRET
    if "--stop" in sys.argv[1:]:
        state = running()
        if state:
            os.kill(state["pid"], signal.SIGTERM)
            print("stopped")
        return 0
    state = running()
    if state:
        print(state["url"])
        return 0
    # Fail early and clearly when Shizuku is not ready.
    try:
        stat("/data")
        listing("/data")
    except Failure as error:
        print("lexona-android-data: " + error.text, file=sys.stderr)
        return 1
    SECRET = secrets.token_urlsafe(12)
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = httpd.server_address[1]
    url = f"dav://localhost:{port}/{SECRET}/"
    if os.fork():
        print(url)
        return 0
    os.setsid()
    log = open(LOG, "a", encoding="utf-8")
    os.dup2(log.fileno(), 2)
    devnull = os.open(os.devnull, os.O_RDWR)
    os.dup2(devnull, 0)
    os.dup2(devnull, 1)
    with open(STATE, "w", encoding="utf-8") as f:
        json.dump({"pid": os.getpid(), "port": port, "url": url}, f)
    bookmark(url)
    signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=httpd.shutdown).start())
    try:
        httpd.serve_forever()
    finally:
        try:
            os.unlink(STATE)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
