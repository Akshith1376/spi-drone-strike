# strike.py - SHADOW-1 aerial strike hud. talks spi via the fpga uart bridge.
#   python strike.py COM5     real board
#   python strike.py          sim mode (fake fpga, same rules as the verilog)
#   python strike.py --live [--speed 1000]    live co-sim: runs the real verilog in icarus (iverilog/vvp on PATH)
#   python strike.py --vivado [--speed 1000]  live link to the vivado sim of tb_x (source sim/xlive.tcl in vivado first)
#   python strike.py --replay trace.txt [--speed 1000]    replay what tb.v wrote (1 sim ms = 1 s at speed 1000)
# keys: 1 arm | 2 launch | SPACE lock | F fire | R rtb | X abort | N new mission | Z clear score | M mute
import sys, os, glob, shutil, subprocess, atexit, socket, time, math, random, threading
from collections import deque
import numpy as np
import pygame
try:
    import serial
except ImportError:
    serial = None

W, H = 1100, 680
VX, VY, VW, VH = 20, 20, 740, 640
GX = GY = 16
CW, CH = VW / GX, VH / GY
GR, RD, YL, DK = (70, 255, 130), (255, 55, 55), (255, 210, 70), (6, 12, 9)
S1N = ["IDLE", "ARMED", "AIRBORNE", "MISSILE AWAY", "RTB", "ABORTED"]
S2N = ["STANDBY", "SEARCHING...", "TARGET FOUND", "LOCKING...", "LOCKED", "IMPACT"]
CN = {0: "NOP", 1: "ARM", 2: "LAUNCH", 3: "START", 4: "DETECT", 5: "HIT", 6: "RTH", 7: "ABORT", 8: "RESET", 9: "AIM"}
SR = 22050


def mk(f0, f1, ms, v=.35, nz=0, dc=0):
    n = int(SR * ms / 1000)
    t = np.arange(n) / SR
    ph = 2 * np.pi * np.cumsum(np.linspace(f0, f1, n)) / SR
    w = np.sin(ph) * (1 - nz) + np.random.uniform(-1, 1, n) * nz
    e = np.minimum(1, np.minimum(np.arange(n) / 150, (n - np.arange(n)) / 300)) * np.exp(-dc * t)
    return pygame.mixer.Sound(buffer=(w * e * v * 32767).astype(np.int16).tobytes())


class Fk:
    # fake fpga so the gui works w/o a board. a=s1 state, b=s2 state, x=aim x
    def __init__(s):
        s.a = s.b = s.x = s.tg = s.h = s.wl = 0
        s.t = 0
    def tx(s, ss, c, d):
        n = time.time()
        if s.b == 1 and n - s.t > 2.0: s.b = 2
        if s.b == 3 and n - s.t > 1.5: s.b = 4
        r = [s.x << 4 | s.a, s.b, ((s.h // 10) << 4) | s.h % 10, s.wl][ss]
        if ss == 0:
            if c == 1 and s.a == 0: s.a = 1
            elif c == 2 and s.a == 1: s.a = 2
            elif c == 5 and s.a == 2: s.a = 3
            elif c == 6 and s.a in (2, 3): s.a = 4
            elif c == 7: s.a = 5
            elif c == 8: s.a = 0
            elif c == 9: s.x = d >> 4
        elif ss == 1:
            if c == 3: s.tg, s.b, s.t = d, 1, n
            elif c == 4 and s.b == 2 and abs((d >> 4) - (s.tg >> 4)) <= 1 and abs((d & 15) - (s.tg & 15)) <= 1:
                s.b, s.t = 3, n
            elif c == 5 and s.b == 4: s.b = 5
            elif c in (6, 7, 8): s.b = 0
        elif ss == 2:
            if c == 5: s.h = (s.h + 1) % 100
            elif c == 8 and d & 1: s.h = 0
        else:
            if c == 7: s.wl = (d & 15) or 15
            elif c == 8: s.wl = 0
        return r


class Lk(threading.Thread):
    # sends queued frames, polls every slave with NOPs when idle. latest status bytes in .v
    def __init__(s, p):
        super().__init__(daemon=True)
        s.f = Fk() if p == "sim" else None
        s.sp = None if s.f else serial.Serial(p, 115200, timeout=0)
        s.q, s.v, s.lg, s.pi, s.buf = deque(), [0, 0, 0, 0], deque(maxlen=14), 0, bytearray()
        s.start()
    def tx(s, ss, c, d=0):
        s.q.append((ss, c, d))
        s.lg.append("S%d <- %-6s %02X" % (ss + 1, CN.get(c, "%02X" % c), d))
    def run(s):
        while True:
            if s.q: ss, c, d = s.q.popleft()
            else:
                ss, c, d = s.pi, 0, 0
                s.pi = (s.pi + 1) % 4
            if s.f:
                s.v[ss] = s.f.tx(ss, c, d)
            else:
                s.sp.write(bytes([0xAA, ss, c, d]))
                time.sleep(.004)
                s.buf += s.sp.read(64)
                while len(s.buf) >= 3:
                    if s.buf[0] != 0x55: del s.buf[0]; continue
                    s.v[s.buf[1] & 3] = s.buf[2]; del s.buf[:3]
            time.sleep(.008)     # fpga needs ~1ms to answer, dont flood it


class Cs(threading.Thread):
    # live co-sim: python <-> vvp (icarus) over pipes, vvp runs the real verilog (uart -> spi -> slaves).
    # sim is paced to the wall clock: 1 sim ms = k/1000 s  (k=1000 -> 1 ms per second, matches TS/TL in tb_live)
    def __init__(s, k=1000.0):
        super().__init__(daemon=True)
        rt = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
        iv, vv = shutil.which("iverilog"), shutil.which("vvp")
        if not iv or not vv: sys.exit("iverilog / vvp not found on PATH - install Icarus Verilog")
        out = os.path.join(rt, "sim", "live.vvp")
        src = sorted(glob.glob(os.path.join(rt, "rtl", "*.v"))) + [os.path.join(rt, "sim", "tb_live.v")]
        subprocess.run([iv, "-g2012", "-o", out] + src, check=True)
        s.p = subprocess.Popen([vv, out], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        atexit.register(s.p.kill)
        s.q, s.v, s.lg, s.k = deque(), [0, 0, 0, 0], deque(maxlen=14), k
        s.start()
    def tx(s, ss, c, d=0):
        s.q.append((ss, c, d))
        s.lg.append("S%d <- %-6s %02X" % (ss + 1, CN.get(c, "%02X" % c), d))
    def rq(s, ln):
        s.p.stdin.write(ln + "\n"); s.p.stdin.flush()
        while True:
            r = s.p.stdout.readline()
            if not r: raise RuntimeError("vvp exited")
            if r.startswith("S "):
                n = [int(x) for x in r.split()[1:]]
                s.v[:] = [n[4] << 4 | n[0], n[1], n[2], n[3]]
                return
    def run(s):
        t0, st = time.time(), 0.0
        try:
            while True:
                if s.q:
                    ss, c, d = s.q.popleft()
                    s.rq("C %d %d %d" % (ss, c, d))      # 4 uart bytes = 34.8 us of sim time
                    s.rq("W 100000 0 0")                  # let bridge + spi finish (100 us)
                    st += 134800
                else:
                    gap = (time.time() - t0) * 1e9 / s.k - st
                    if gap >= 20000: s.rq("W %d 0 0" % int(gap)); st += int(gap)
                    else: time.sleep(.003)
        except (RuntimeError, OSError, ValueError):
            pass                                          # vvp closed (window quit)


class Xs(threading.Thread):
    # live link to vivado's simulator (tb_x) through the tcl socket server in xlive.tcl. no uart, straight into spi.
    # sim paced to wall clock: 1 sim ms = k/1000 s
    def __init__(s, k=1000.0, port=5555):
        super().__init__(daemon=True)
        for _ in range(40):
            try: s.sk = socket.create_connection(("127.0.0.1", port), 2); break
            except OSError: time.sleep(.5)
        else: sys.exit("cant reach vivado on port %d - run the sim of tb_x and 'source xlive.tcl' in its tcl console" % port)
        s.sk.settimeout(None)
        s.f = s.sk.makefile("r")
        s.q, s.v, s.lg, s.k = deque(), [0, 0, 0, 0], deque(maxlen=14), k
        s.start()
    def tx(s, ss, c, d=0):
        s.q.append((ss, c, d))
        s.lg.append("S%d <- %-6s %02X" % (ss + 1, CN.get(c, "%02X" % c), d))
    def rq(s, ln):
        s.sk.sendall((ln + "\n").encode())
        while True:
            r = s.f.readline()
            if not r: raise RuntimeError("vivado closed the link")
            if r.startswith("S "):
                n = [int(x) for x in r.split()[1:]]
                s.v[:] = [n[4] << 4 | n[0], n[1], n[2], n[3]]
                return
    def run(s):
        t0, st = time.time(), 0.0
        try:
            while True:
                if s.q:
                    ss, c, d = s.q.popleft()
                    s.rq("C %d %d %d" % (ss, c, d))       # tcl runs ~80 ns + 20 us of sim for one frame
                    st += 20080
                else:
                    gap = (time.time() - t0) * 1e9 / s.k - st
                    if gap >= 50000: s.rq("W %d 0 0" % int(gap)); st += int(gap)
                    else: time.sleep(.003)
        except (RuntimeError, OSError, ValueError):
            pass


class Rp(threading.Thread):
    # replays trace.txt from tb.v. the status bytes + frames come from the verilog sim, not from python
    def __init__(s, fn, k=1000.0):
        super().__init__(daemon=True)
        s.ev, s.v, s.lg, s.aim, s.k, s.done = deque(), [0, 0, 0, 0], deque(maxlen=14), (0, 0), k, False
        s.rows = [w for w in (l.split() for l in open(fn)) if len(w) > 2 and w[1] in ("C", "S")]
        s.start()
    def tx(s, *a): pass
    def run(s):
        t0 = time.time() + 1.0
        for w in s.rows:
            while time.time() < t0 + float(w[0]) * s.k / 1e6: time.sleep(.003)
            n = [int(x) for x in w[2:]]
            if w[1] == "C":
                ss, c, d = n
                s.lg.append("S%d <- %-6s %02X" % (ss + 1, CN.get(c, "%02X" % c), d))
                if c in (4, 9) and ss in (0, 1): s.aim = (d >> 4, d & 15)
                s.ev.append((ss, c, d))
            else:
                s.v[:] = [n[4] << 4 | n[0], n[1], n[2], n[3]]
        s.done = True


class Gm:
    def __init__(s):
        s.p2 = 0
        s.new()
    def new(s):
        s.n = getattr(s, "n", 16) + 1
        s.tg = (random.randrange(16), random.randrange(16))
        s.tid, s.wd, s.ds = random.randint(1, 9), random.choice(["LEFT", "RIGHT", "NONE"]), random.randint(20, 99)
        s.mst = s.imp = s.chk = s.ex = None
        s.lkt = s.nxt = s.mt = 0
        s.msg = ""
        s.mp = (0, 0)
    def say(s, t, now):
        s.msg, s.mt = t, now + 2.0


def mkbg():
    random.seed(7)
    s = pygame.Surface((VW, VH))
    s.fill((5, 16, 11))
    for _ in range(14):
        pygame.draw.line(s, (14, 40, 26), (random.randrange(VW), 0), (random.randrange(VW), VH), random.randint(3, 7))
        pygame.draw.line(s, (14, 40, 26), (0, random.randrange(VH)), (VW, random.randrange(VH)), random.randint(3, 7))
    for _ in range(320):
        x, y, w, h = random.randrange(VW), random.randrange(VH), random.randint(8, 50), random.randint(8, 36)
        c = random.randint(14, 44)
        pygame.draw.rect(s, (c // 2, c + 12, c // 2 + 4), (x, y, w, h))
        if random.random() < .35:
            pygame.draw.rect(s, (200, 170, 60), (x + 2, y + 2, 2, 2))
    for i in range(GX + 1): pygame.draw.line(s, (16, 50, 30), (i * CW, 0), (i * CW, VH))
    for i in range(GY + 1): pygame.draw.line(s, (16, 50, 30), (0, i * CH), (VW, i * CH))
    random.seed()
    return s


def brk(s, c, cx, cy, h, l, w=2):
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = cx + sx * h, cy + sy * h
            pygame.draw.line(s, c, (x, y), (x - sx * l, y), w)
            pygame.draw.line(s, c, (x, y), (x, y - sy * l), w)


def xh(s, c, cx, cy):
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        pygame.draw.line(s, c, (cx + dx * 10, cy + dy * 10), (cx + dx * 38, cy + dy * 38), 1)
    pygame.draw.circle(s, c, (cx, cy), 3, 1)


def main():
    pygame.mixer.pre_init(SR, -16, 1, 256)
    pygame.init()
    scr = pygame.display.set_mode((W, H))
    pygame.display.set_caption("SHADOW-1 // SPI STRIKE")
    f1 = pygame.font.SysFont("consolas,couriernew,monospace", 16)
    f2 = pygame.font.SysFont("consolas,couriernew,monospace", 30, bold=True)
    av = sys.argv[1:]
    rep = "--replay" in av
    spd = float(av[av.index("--speed") + 1]) if "--speed" in av else 1000.0
    if rep:
        lk = Rp(av[av.index("--replay") + 1], spd)
    elif "--live" in av:
        lk = Cs(spd)
    elif "--vivado" in av:
        lk = Xs(spd)
    else:
        lk = Lk(av[0] if av else "sim")
    sn = dict(arm=mk(700, 900, 90), ping=mk(900, 1500, 220), lb=mk(1900, 1900, 60), lock=mk(2300, 2300, 700),
              fire=mk(1800, 150, 900, .35, .5, 1.5), boom=mk(90, 25, 1500, .9, .6, 2.5), err=mk(160, 160, 350, .35, .2))
    mute = False
    def play(k):
        if not mute: sn[k].play()
    bg = mkbg()
    sl = pygame.Surface((VW, VH), pygame.SRCALPHA)
    for y in range(0, VH, 3): pygame.draw.line(sl, (0, 0, 0, 55), (0, y), (VW, y))
    g, ck, la, lat = Gm(), pygame.time.Clock(), (-1, -1), 0

    while True:
        now = time.time()
        v = lk.v
        a1, a2 = v[0] & 7, v[1] & 7
        hits, wl = (v[2] >> 4) * 10 + (v[2] & 15), v[3] & 15
        mx, my = pygame.mouse.get_pos()
        px, py = min(max(mx - VX, 0), VW - 1), min(max(my - VY, 0), VH - 1)
        ax, ay = int(px // CW), int(py // CH)
        if rep:
            ax, ay = lk.aim
            px, py = int((ax + .5) * CW), int((ay + .5) * CH)

        for e in pygame.event.get():
            if e.type == pygame.QUIT: return
            if e.type != pygame.KEYDOWN: continue
            k = e.key
            if k == pygame.K_ESCAPE: return
            elif k == pygame.K_m: mute = not mute
            elif rep: pass
            elif k == pygame.K_1:
                if a1 == 0: lk.tx(0, 1); play("arm")
                else: play("err")
            elif k == pygame.K_2:
                if a1 == 1:
                    lk.tx(0, 2); lk.tx(1, 3, g.tg[0] << 4 | g.tg[1]); lk.tx(2, 3); play("arm")
                else: play("err"); g.say("ARM FIRST", now)
            elif k == pygame.K_SPACE:
                if a2 == 2:
                    lk.tx(1, 4, ax << 4 | ay); g.chk = now + .4
                else: play("err"); g.say("NO TARGET YET", now)
            elif k == pygame.K_f:
                if a1 == 2 and g.mst is None:
                    lk.tx(0, 5); play("fire"); g.mst, g.mp = now, (px, py)
                else: play("err")
            elif k == pygame.K_r: lk.tx(0, 6); lk.tx(1, 6)
            elif k == pygame.K_x:
                lk.tx(0, 7); lk.tx(1, 7); lk.tx(3, 7, 8); play("err"); g.say("MISSION ABORTED", now)
            elif k == pygame.K_n:
                for ss in (0, 1, 2, 3): lk.tx(ss, 8)
                g.new()
            elif k == pygame.K_z: lk.tx(2, 8, 1)

        while rep and lk.ev:
            ss, c, d = lk.ev.popleft()
            if ss == 0 and c in (1, 2): play("arm")
            elif ss == 1 and c == 3: g.tg = (d >> 4, d & 15)
            elif ss == 1 and c == 4: g.chk = now + .4
            elif ss == 0 and c == 5: play("fire"); g.mst, g.mp = now, (px, py)
        if rep and lk.done and now > g.mt: g.say("REPLAY DONE - ESC TO QUIT", now)

        if a1 in (1, 2) and (ax, ay) != la and now - lat > .06:
            lk.tx(0, 9, ax << 4 | ay); la, lat = (ax, ay), now

        # state changes coming back from the slaves
        if a2 != g.p2:
            if a2 == 2: play("ping")
            if a2 == 3: g.lkt = g.nxt = now; g.chk = None
            if a2 == 4: play("lock"); lk.tx(3, 4); g.say("TARGET LOCKED - FIRE", now)
            if a2 == 5:
                play("boom"); g.ex, g.imp = now, None
                lk.tx(2, 5); lk.tx(3, 5); g.say("IMPACT - TARGET DESTROYED", now)
            g.p2 = a2
        if a2 == 3 and now >= g.nxt:
            play("lb"); g.nxt = now + max(.05, .28 - .15 * (now - g.lkt))
        if g.chk and now > g.chk:
            if a2 == 2:
                play("err"); lk.tx(3, 7, 1); g.say("NO LOCK - ADJUST AIM", now)
            g.chk = None
        if g.imp and now - g.imp > .8 and a2 != 5:
            g.imp = None; play("err"); g.say("IMPACT FAILED", now)

        # ---- draw ----
        vw = bg.copy()
        pygame.draw.rect(vw, (30, 110, 60), (ax * CW, ay * CH, CW, CH), 1)
        tcx, tcy = g.tg[0] * CW + CW / 2, g.tg[1] * CH + CH / 2
        if 2 <= a2 <= 4:
            sz = 40 if a2 == 2 else (40 - 16 * min(1, (now - g.lkt) / 1.5) if a2 == 3 else 24)
            pygame.draw.rect(vw, RD, (tcx - sz, tcy - sz, sz * 2, sz * 2), 3)
            pygame.draw.circle(vw, RD, (tcx, tcy), 3)
        col = RD if a2 == 4 else GR
        brk(vw, col, px, py, 56, 18)
        xh(vw, col, px, py)

        sx = sy = 0
        if g.mst:
            p = (now - g.mst) / 1.1
            if p < 1:
                x0, y0 = VW / 2, VH + 10
                for i in range(9):
                    q = max(0, p - i * .018)
                    pygame.draw.circle(vw, YL if i < 2 else (200, 120, 40), (x0 + (g.mp[0] - x0) * q, y0 + (g.mp[1] - y0) * q), max(1, 5 - i // 2))
            else:
                g.mst = None
                if rep: pass
                elif a2 == 4: lk.tx(1, 5); g.imp = now
                else: play("err"); lk.tx(3, 7, 4); g.say("MISSILE MISSED - NO LOCK", now)
        if g.ex:
            t = now - g.ex
            if t < 1.4:
                r, f = int(t * 260), 1 - t / 1.4
                pygame.draw.circle(vw, (255, int(240 * f), int(120 * f)), (tcx, tcy), max(1, int(r * .6)))
                pygame.draw.circle(vw, (255, 150, 40), (tcx, tcy), max(2, r), 5)
                if t < .5: sx, sy = random.randint(-8, 8), random.randint(-8, 8)
        vw.blit(sl, (0, 0))

        def tt(s, f, t, c, x, y): s.blit(f.render(t, True, c), (x, y))
        for i, t in enumerate(["SHADOW-1  ONLINE", "MISSION #%d" % g.n, "TARGET:  T%d" % g.tid,
                               "WIND:    " + g.wd, "DISTANCE: %d" % g.ds, "AIM  X%02d Y%02d" % (ax, ay)]):
            tt(vw, f1, t, GR, 14, 12 + i * 20)
        bn = g.msg if now < g.mt else (S2N[a2] if a2 else S1N[min(a1, 5)])
        bc = YL if now < g.mt else (RD if a2 >= 4 else GR)
        im = f2.render(bn, True, bc)
        vw.blit(im, (VW / 2 - im.get_width() / 2, VH - 60))

        scr.fill(DK)
        scr.blit(vw, (VX + sx, VY + sy))
        pygame.draw.rect(scr, GR, (VX - 2, VY - 2, VW + 4, VH + 4), 2)
        x0 = VX + VW + 24
        tt(scr, f1, "// SPI BUS", GR, x0, 20)
        for i, (n_, s_) in enumerate([("S1 FLIGHT", S1N[min(a1, 5)]), ("S2 TARGET", S2N[a2 if a2 < 6 else 0]),
                                      ("S3 TELEM", "HITS %02d" % hits), ("S4 FAULT", "WARN %s" % format(wl, "04b") if wl else "OK")]):
            tt(scr, f1, n_, (140, 200, 160), x0, 52 + i * 44)
            tt(scr, f1, s_, RD if (i == 3 and wl) else GR, x0 + 12, 52 + i * 44 + 18)
        tt(scr, f1, "// MOSI LOG", GR, x0, 250)
        for i, t in enumerate(lk.lg): tt(scr, f1, t, (110, 190, 130), x0, 276 + i * 18)
        for i, t in enumerate(["1 arm   2 launch", "SPACE lock  F fire", "R rtb  X abort", "N new  Z score  M mute"]):
            tt(scr, f1, t, (90, 150, 110), x0, 560 + i * 20)
        if mute: tt(scr, f1, "MUTED", YL, x0, 640)
        if rep: tt(scr, f1, "REPLAY of tb.v trace", YL, x0, 620)
        pygame.display.flip()
        ck.tick(60)


if __name__ == "__main__":
    main()
