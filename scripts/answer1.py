"""Answer a blocked dialog with key "1" through an attach client in a PTY.

Usage: answer1.py <sid> <cli> <cols> <rows>
Every argument is required; no silent defaults. The CLI is a path to a
`pohunek` binary reached through the rig wrapper (cli.sh <rig-root>),
never spliced into code here. Exits non-zero on attach timeout or a
non-zero attach exit; the attach client is always killed on timeout.
"""
import fcntl
import os
import pty
import struct
import subprocess
import sys
import termios
import time


def usage():
    sys.stderr.write("answer1: usage: answer1.py <sid> <cli> <cols> <rows>\n")


def main():
    if len(sys.argv) != 5:
        usage()
        return 2
    _, sid, cli, cols_s, rows_s = sys.argv
    if not sid or not cli:
        usage()
        return 2
    try:
        cols = int(cols_s)
        rows = int(rows_s)
    except ValueError:
        sys.stderr.write("answer1: cols/rows must be integers\n")
        return 2
    if cols <= 0 or rows <= 0:
        sys.stderr.write("answer1: cols/rows must be positive\n")
        return 2
    if not (os.path.isfile(cli) and os.access(cli, os.X_OK)):
        sys.stderr.write(f"answer1: cli is not an executable file: {cli}\n")
        return 2
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    try:
        proc = subprocess.Popen([cli, "attach", sid], stdin=slave,
                                stdout=slave, stderr=slave, close_fds=True,
                                start_new_session=True)
    except OSError as e:
        sys.stderr.write(f"answer1: cannot start attach: {e}\n")
        os.close(slave)
        os.close(master)
        return 1
    os.close(slave)
    rc = 1
    try:
        time.sleep(0.6)
        os.write(master, b"1")
        time.sleep(0.6)
        os.write(master, b"\x1d")
        try:
            rc = proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            sys.stderr.write("answer1: attach timed out, killing\n")
            proc.kill()
            try:
                rc = proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                sys.stderr.write("answer1: attach kill timed out\n")
                rc = 1
        if rc != 0:
            sys.stderr.write(f"answer1: attach exited {rc}\n")
    except OSError as e:
        sys.stderr.write(f"answer1: pty error: {e}\n")
        proc.kill()
        rc = 1
    finally:
        os.close(master)
    return rc


if __name__ == "__main__":
    sys.exit(main())
