#!/usr/bin/python3
"""x11-seticon: sharp icons for web app windows (Chromium --app) in the XFCE panel.

Chromium gives --app windows only a small favicon (blurry in the panel) and the class
"Chromium". The daemon watches windows whose WM_CLASS res_name is in the configuration,
sets their class to the res_name (so StartupWMClass in the .desktop matches) and sets
_NET_WM_ICON from a large PNG in several sizes. When Chromium overwrites the icon (favicon
change), it puts it back. With "badge" it draws a red badge with the count from the window
title "... (N) ..." (Gmail).

Configuration (--config), one line = res_name  path_to_png  [badge]   (# comment):
    mail.google.com  /.../icons/webapps/gmail.png  badge

Runs in Debian (python3-xlib, python3-pil, fonts-dejavu-core):
    debian-run python3 x11-seticon.py --config ...

Status: manual tool from the Galaxy Z Fold 7 (2026-11-19), not shipped in the APK yet.
"""
import argparse
import re
import sys
import time

from PIL import Image, ImageDraw, ImageFont
from Xlib import X, Xatom, display, error

SIZES = (16, 24, 32, 48, 64, 128)  # under 256 KB in total: python-xlib has no BIG-REQUESTS
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
COUNT_RE = re.compile(r"\((\d+)\)")


def load_config(path):
    apps = {}
    with open(path) as f:
        for line in f:
            line = line.split("#", 1)[0].split()
            if len(line) >= 2:
                apps[line[0]] = (line[1], "badge" in line[2:])
    return apps


def draw_badge(img, count):
    s = img.size[0]
    text = "99+" if count > 99 else str(count)
    d = ImageDraw.Draw(img)
    r = round(s * (0.30 if len(text) == 1 else 0.34))
    cx, cy = s - r, r
    w = r if len(text) == 1 else round(r * (1.0 + 0.25 * (len(text) - 1)))
    d.rounded_rectangle((cx - w, cy - r, s - 1, cy + r), radius=r, fill=(217, 48, 37, 255),
                        outline=(255, 255, 255, 255), width=max(1, s // 32))
    try:
        font = ImageFont.truetype(FONT, round(r * (1.25 if len(text) == 1 else 1.0)))
    except OSError:
        font = ImageFont.load_default()
    d.text(((cx - w + s - 1) / 2, cy), text, fill="white", font=font, anchor="mm")
    return img


class Icons:
    def __init__(self):
        self.cache = {}

    def get(self, path, count):
        key = (path, count)
        if key not in self.cache:
            base = Image.open(path).convert("RGBA")
            data = []
            for s in SIZES:
                im = base.resize((s, s), Image.LANCZOS)
                if count:
                    im = draw_badge(im, count)
                data += [s, s]
                data += [(a << 24) | (r << 16) | (g << 8) | b for r, g, b, a in im.getdata()]
            self.cache[key] = data
        return self.cache[key]


class Daemon:
    def __init__(self, apps):
        self.apps = apps
        self.icons = Icons()
        self.d = display.Display()
        self.d.set_error_handler(lambda *a: None)  # BadWindow on closed windows must not kill the daemon
        self.root = self.d.screen().root
        self.root.change_attributes(event_mask=X.PropertyChangeMask)
        a = self.d.intern_atom
        self.CLIENTS, self.ICON = a("_NET_CLIENT_LIST"), a("_NET_WM_ICON")
        self.NAME, self.UTF8 = a("_NET_WM_NAME"), a("UTF8_STRING")
        self.wins = {}  # wid -> [window, res_name, count, data]

    def title(self, w):
        try:
            p = w.get_full_property(self.NAME, self.UTF8)
            if p:
                return p.value.decode("utf-8", "replace")
            return w.get_wm_name() or ""
        except error.XError:
            return ""

    def apply(self, wid, force=False):
        w, name, count, data = self.wins[wid]
        path, badge = self.apps[name]
        if badge:
            m = COUNT_RE.search(self.title(w))
            count = int(m.group(1)) if m else 0
        new = self.icons.get(path, count)
        if not force and new is data:
            try:  # Chromium may have overwritten the icon
                cur = w.get_full_property(self.ICON, Xatom.CARDINAL)
                if cur is not None and list(cur.value) == new:
                    return
            except error.XError:
                return
        w.change_property(self.ICON, Xatom.CARDINAL, 32, new)
        self.wins[wid] = [w, name, count, new]

    def scan(self):
        try:
            p = self.root.get_full_property(self.CLIENTS, Xatom.WINDOW)
        except error.XError:
            return
        ids = set(p.value) if p else set()
        for wid in list(self.wins):
            if wid not in ids:
                del self.wins[wid]
        for wid in ids - set(self.wins):
            w = self.d.create_resource_object("window", wid)
            try:
                cls = w.get_wm_class()
            except error.XError:
                continue
            if not cls or cls[0] not in self.apps:
                continue
            name = cls[0]
            try:
                w.change_attributes(event_mask=X.PropertyChangeMask)
                if cls[1] != name:
                    w.set_wm_class(name, name)
                self.wins[wid] = [w, name, None, None]
                self.apply(wid, force=True)
            except error.XError:
                self.wins.pop(wid, None)
        self.d.flush()

    def run(self):
        self.scan()
        while True:
            ev = self.d.next_event()
            if ev.type != X.PropertyNotify:
                continue
            if ev.window == self.root:
                if ev.atom == self.CLIENTS:
                    self.scan()
                continue
            wid = ev.window.id
            if wid in self.wins and ev.atom in (self.ICON, self.NAME, Xatom.WM_NAME):
                try:
                    self.apply(wid)
                    self.d.flush()
                except error.XError:
                    pass


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--config", required=True)
    args = ap.parse_args()
    apps = load_config(args.config)
    while True:  # reconnect when the X connection drops (DeX <-> phone switch)
        try:
            Daemon(apps).run()
        except (error.ConnectionClosedError, error.DisplayError, OSError) as e:
            print("x11-seticon: %s, retrying in 3 s" % e, file=sys.stderr)
            time.sleep(3)


if __name__ == "__main__":
    main()
