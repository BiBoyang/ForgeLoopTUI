#!/usr/bin/env python3
"""TASK-29 long unclosed-fence preview soak for MinimalAIApp.

Streams Examples/Fixtures/markdown-long-fence-soak.md via `/demo soak`: the
whole fixture lives inside a single code fence (>100 lines), so the streaming
engine certifies nothing stable until the closing fence arrives — every line
previews through the committed region of `render(committed:live:)`, exceeding
the terminal height and hitting the library's documented ESC[2J full-redraw
fallback on every frame. Mid-stream the PTY is resized 24x80 -> 30x100.

Asserts: preview is live early, preview survives the resize, settled lines
appear exactly once in fixture order (terminal state == static render order),
and no settled line is ever re-emitted by later renders.
"""
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
    env.pop("DEEPSEEK_API_KEY", None)  # force offline path for determinism

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

    EARLY = b"SOAKMARK-EARLY"
    TABLE_ROW = b"SOAKMARK-TABLE-ROW"
    PY = b"SOAKMARK-PY"
    MID = b"SOAKMARK-MID"
    JS = b"SOAKMARK-JS"
    CJK = b"SOAKMARK-CJK"
    LATE = b"SOAKMARK-LATE"
    TAIL = b"SOAKMARK-TAIL"

    # 1. initial render
    check("initial render shows idle status + prompt",
          wait_for(master, IDLE + rb".*\xe2\x9d\xaf "))

    # 2. stream the long-fence fixture
    s0 = len(BUF)
    os.write(master, b"/demo soak\r")
    check("soak: streaming starts", wait_for(master, STREAMING, 5, start=s0))

    # 3. preview is live: an early fence line is visible long before the tail
    #    exists. BUF only grows inside pump/wait_for, so this snapshot is
    #    exactly what had arrived when EARLY first matched.
    check("soak: early fence line previews mid-stream",
          wait_for(master, EARLY, 10, start=s0))
    snapshot = bytes(BUF)
    check("soak: preview is intermediate (tail not yet streamed)",
          TAIL not in snapshot[s0:])

    # 4. mid-stream resize 24x80 -> 30x100 (the app polls the terminal size on
    #    every render, so the next token frame picks it up).
    check("soak: mid marker reached", wait_for(master, MID, 15, start=s0))
    set_winsz(master, 30, 100)

    # 5. stream completes and the app returns to idle after the resize.
    check("soak: tail line arrives", wait_for(master, TAIL, 30, start=s0))
    check("soak: returns to idle after resize", wait_for(master, IDLE, 10, start=s0))
    pump(master, 0.5)

    # 6. Post-resize preview stayed alive: LATE only streams after the resize,
    #    so its FIRST occurrence must come from a live preview frame — i.e. a
    #    streaming status line follows it within the same frame, not from the
    #    closing-fence settle (which is followed by idle). Evaluated only
    #    after completion so the frame tail is guaranteed to have arrived.
    #    The window is generous on purpose: full-redraw frames are ~4KB, and
    #    nothing after the final settle can contain a streaming status.
    i_late = BUF.find(LATE, s0)
    late_context = bytes(BUF[i_late:i_late + 5000]) if i_late != -1 else b""
    check("soak: post-resize line previews before settling (resize soak)",
          i_late != -1 and re.search(STREAMING, late_context) is not None)

    # 7. Terminal state == static render order: nothing inside the unclosed
    #    fence can settle early, so the closing fence commits the whole block
    #    in one appendFrame; the LAST occurrence of each marker is that
    #    settle (settled lines are never rewritten afterwards), and settles
    #    happen in source order.
    markers = [EARLY, TABLE_ROW, PY, MID, JS, CJK, LATE, TAIL]
    last = [BUF.rfind(m) for m in markers]
    check("soak: settled line order matches fixture order",
          all(i != -1 for i in last) and all(a < b for a, b in zip(last, last[1:])))

    # 8. No duplicate commits: forcing further renders after completion must
    #    not re-emit any settled fixture line.
    d1 = len(BUF)
    os.write(master, b"x")
    check("post-soak input echoes", wait_for(master, rb"\xe2\x9d\xaf x", 5, start=d1))
    os.write(master, b"\x7f")  # backspace: render again with an empty input
    pump(master, 0.4)
    tail = bytes(BUF[d1:])
    check("soak: settled lines never re-emit after completion",
          all(m not in tail for m in markers))

    proc.kill()
    pump(master, 0.2)

    if failures:
        print(f"\n{len(failures)} FAILURES: {failures}")
        sys.stdout.write(repr(bytes(BUF[-3000:])))
        sys.exit(1)
    print(f"\nALL PASS — captured {len(BUF)} bytes of PTY output")

if __name__ == "__main__":
    main()
