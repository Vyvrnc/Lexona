#!/usr/bin/env python3
"""lexona-host CMD [ARGS...]: run a command outside the calling process tree.

Lexona's app starts CMD with Termux's environment (PATH: Termux's bin, debian-run, ...)
and streams its output back; the exit status is CMD's. For sessions under proot (Claude
Code in Lexona), where apt and a nested debian-run hang:
    lexona-host debian-run apt-get install -y /root/downloads/x.deb
CMD gets no input, so give apt -y. It keeps running when this client is interrupted.
"""
import json
import os
import socket
import sys

SOCKET = "\0lexona.host"
MARK = b"\0LEXONA-EXIT:"


def main():
    argv = sys.argv[1:]
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if argv else 2
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.connect(SOCKET)
    except OSError as error:
        print("lexona-host: Lexona's host bridge is not running (%s); open Lexona once." % error,
              file=sys.stderr)
        return 125
    try:
        cwd = os.getcwd()
    except OSError:
        cwd = ""
    client.sendall((json.dumps({"argv": argv, "cwd": cwd}) + "\n").encode())
    out = sys.stdout.buffer
    pending = b""
    while True:
        chunk = client.recv(65536)
        if not chunk:
            break
        pending += chunk
        at = pending.find(MARK)
        if at >= 0:
            out.write(pending[:at])
            out.flush()
            rest = pending[at + len(MARK):].split(b"\n", 1)[0]
            try:
                return int(rest.strip() or b"1")
            except ValueError:
                return 1
        # Keep a tail that could be the start of the mark.
        keep = len(MARK) - 1
        if len(pending) > keep:
            out.write(pending[:-keep])
            out.flush()
            pending = pending[-keep:]
    out.write(pending)
    out.flush()
    print("lexona-host: connection closed before the command ended", file=sys.stderr)
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
