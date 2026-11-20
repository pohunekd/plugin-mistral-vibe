"""Refusing egress proxy for the Vibe capture rig.

Run: python3 -I proxy.py --port N --log FILE

Accepts a connection, logs the request line (method and target; no headers)
and answers 403 to every request, so CONNECT never tunnels anywhere.
"""
from __future__ import annotations

import argparse
import socketserver
import threading
import time

LOCK = threading.Lock()
LOGF = None


class H(socketserver.StreamRequestHandler):
    def handle(self):
        try:
            line = self.rfile.readline(4096).decode("latin-1").strip()
            while True:  # drain headers without recording them
                h = self.rfile.readline(4096)
                if not h or h in (b"\r\n", b"\n"):
                    break
            with LOCK:
                with open(LOGF, "a", encoding="utf-8") as fh:
                    fh.write(f"{time.strftime('%H:%M:%S')} {line}\n")
            self.wfile.write(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        except OSError:
            pass


class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    global LOGF
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--log", required=True)
    a = ap.parse_args()
    LOGF = a.log
    with open(LOGF, "a", encoding="utf-8") as fh:
        fh.write(f"{time.strftime('%H:%M:%S')} proxy listening 127.0.0.1:{a.port}\n")
    S(("127.0.0.1", a.port), H).serve_forever()


if __name__ == "__main__":
    main()
