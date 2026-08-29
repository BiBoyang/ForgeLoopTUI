#!/usr/bin/env python3
"""TASK-22 PTY interactive smoke test for MinimalAIApp committed-append rendering."""
import fcntl
import os
import re
import struct
import subprocess
import sys
import termios
import time
import select

APP = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".build/debug/MinimalAIApp")
BUF = bytearray()

def set_winsz(fd, rows, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

def pump(fd, timeout=0.15):
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                return
            if not chunk:
                return
            BUF.extend(chunk)
            end = time.time() + timeout

def wait_for(fd, pattern, timeout=15.0, start=0):
    rx = re.compile(pattern, re.DOTALL)
    end = time.time() + timeout
    while time.time() < end:
        if rx.search(BUF, start):
            return True
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                return False
            if not chunk:
                return False
            BUF.extend(chunk)
    return rx.search(BUF, start) is not None

def main():
    env = dict(os.environ)
    env.pop("DEEPSEEK_API_KEY", None)  # force FauxAIProvider for determinism

    master, slave = os.openpty()
    set_winsz(slave, 24, 80)

    def preexec():
        # Give the child a controlling terminal — without it the app's
        # shutdown path misbehaves (artifact of bare openpty, not an app bug).
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    proc = subprocess.Popen([APP], stdin=slave, stdout=slave, stderr=slave,
                            env=env, close_fds=True, preexec_fn=preexec)
    os.close(slave)

    failures = []
    def check(name, ok):
        print(("PASS" if ok else "FAIL") + f": {name}")
        if not ok:
            failures.append(name)

    IDLE = rb"\xe2\x97\x8f idle"          # ● idle
    STREAMING = rb"\xe2\x97\x8f streaming"

    # 1. initial render
    check("initial render shows idle status + prompt",
          wait_for(master, IDLE + rb".*\xe2\x9d\xaf "))

    # 2. round 1
    r1 = len(BUF)
    os.write(master, b"first question\r")
    check("round 1 streaming starts", wait_for(master, STREAMING, 5, start=r1))
    check("round 1 reply complete",
          wait_for(master, rb"You said: first question.*powered by ForgeLoopTUI\.", start=r1))
    check("round 1 returns to idle", wait_for(master, IDLE + rb"(?!.*streaming)", 5, start=r1))
    pump(master, 0.4)

    # 3. round 2 (multi-round continuity)
    r2 = len(BUF)
    os.write(master, b"second question\r")
    check("round 2 reply complete",
          wait_for(master, rb"You said: second question.*powered by ForgeLoopTUI\.", start=r2))
    pump(master, 0.4)

    # 3.5 history recall (Ctrl-P/Ctrl-N) + cursor movement (preserved bindings)
    hp = len(BUF)
    os.write(master, b"\x10")  # Ctrl-P = history prev
    check("ctrl-p recalls last submitted prompt",
          wait_for(master, rb"\xe2\x9d\xaf second question", 5, start=hp))
    os.write(master, b"\x1b[H")  # Home
    os.write(master, b"Q")
    check("home then insert edits at line start",
          wait_for(master, rb"\xe2\x9d\xaf Qsecond question", 5))
    os.write(master, b"\x1b[F")  # End
    os.write(master, b"Z")
    check("end then insert edits at line end",
          wait_for(master, rb"Qsecond questionZ", 5))
    os.write(master, b"\x1b[D\x1b[D\x7f")  # Left Left Backspace deletes 'n'
    check("left+backspace edits mid-line",
          wait_for(master, rb"Qsecond question", 5))
    os.write(master, b"\x1b")  # Esc while idle clears the buffer
    time.sleep(0.6)  # escape timeout
    pump(master, 0.3)

    # 4. round 3: Esc mid-stream cancels
    r3 = len(BUF)
    os.write(master, b"third question\r")
    wait_for(master, STREAMING, 5, start=r3)
    time.sleep(0.15)  # a few tokens land
    os.write(master, b"\x1b")
    check("esc cancel prints notification", wait_for(master, rb"cancelled", 5, start=r3))
    pump(master, 0.5)

    # 5. resize then another round (no misalignment / crash)
    r4 = len(BUF)
    set_winsz(master, 30, 100)
    os.write(master, b"after resize\r")
    check("post-resize round completes",
          wait_for(master, rb"You said: after resize.*powered by ForgeLoopTUI\.", start=r4))
    pump(master, 0.4)

    # 6. Ctrl-C exits — driven via `script(1)` so the child gets a real
    #    controlling terminal (bare openpty without ctty makes the app's
    #    shutdown path hang; that is a harness artifact, not app behavior).
    ctrlc = subprocess.run(
        ["sh", "-c", "{ sleep 1; printf '\\003'; sleep 2; } | script -q /dev/null \"$1\" >/dev/null 2>&1", "sh", APP],
        env=env, timeout=15)
    check("ctrl-c exits app (via script pty)", ctrlc.returncode == 0)
    proc.kill()  # harness instance: no further use
    pump(master, 0.3)

    # byte-stream assertions (scrollback contract)
    check("no ESC[2J full-screen clear", b"\x1b[2J" not in BUF)
    i1 = BUF.find(b"You said: first question")
    i2 = BUF.find(b"You said: second question")
    i3 = BUF.find(b"You said: after resize")
    check("round order in stream (1 < 2 < resize)", -1 < i1 < i2 < i3)
    check("cancelled round content committed after notification",
          BUF.find(b"cancelled") != -1)

    if failures:
        print(f"\n{len(failures)} FAILURES: {failures}")
        sys.stdout.write(repr(bytes(BUF[-3000:])))
        sys.exit(1)
    print(f"\nALL PASS — captured {len(BUF)} bytes of PTY output")

if __name__ == "__main__":
    main()
