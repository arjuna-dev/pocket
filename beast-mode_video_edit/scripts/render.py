#!/usr/bin/env python3
"""Render the Beast Mode video (video track only).

Segments (24 fps, 1920x1080):
  A  static Pocket logo card (intro narration)
  B  over-the-top BEAST MODE / GOD MODE reveal
  C  the screen recording with God Mode captions
  D  closing logo card

Usage:
  render.py                 render the full video-only master
  render.py preview A:5 B:0.7 B:6.2 C:10 D:2     write PNG previews to exports/preview
"""
import math, os, random, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1920, 1080, 24
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = f"{ROOT}/source/beast-mode.mp4"
LOGO = f"{ROOT}/assets/pocket-logo.png"
OUT = f"{ROOT}/exports/video-only.mov"
PREV = f"{ROOT}/exports/preview"
IMPACT = "/System/Library/Fonts/Supplemental/Impact.ttf"
ARIAL_B = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

A_FR, B_FR, C_FR, D_FR = 590, 192, 1664, 110
CX, CY = W / 2, H / 2

yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
DX, DY = xx - CX, yy - CY
R = np.sqrt(DX * DX + DY * DY)
ANG = np.arctan2(DY, DX)
RN = R / math.hypot(CX, CY)
VIGNETTE = (1 - 0.55 * RN ** 2)[..., None].astype(np.float32)
del xx, yy


# ---------------------------------------------------------------- helpers
def ease_out(x):
    x = min(1.0, max(0.0, x))
    return 1 - (1 - x) ** 3


def text_sprite(txt, path, size, stops, stroke=14, outline=10):
    f = ImageFont.truetype(path, size)
    pad = outline + stroke + 20
    l, t, r, b = f.getbbox(txt)
    w, h = r - l + 2 * pad, b - t + 2 * pad

    def mask(sw):
        m = Image.new("L", (w, h), 0)
        ImageDraw.Draw(m).text((pad - l, pad - t), txt, font=f, fill=255,
                               stroke_width=sw, stroke_fill=255)
        return m

    ys = np.clip((np.arange(h) - pad) / max(1, (b - t)), 0, 1)
    pos = np.linspace(0, 1, len(stops))
    col = np.stack([np.interp(ys, pos, [s[c] for s in stops]) for c in range(3)], axis=1)
    grad = np.broadcast_to(col[:, None, :], (h, w, 3)).astype(np.uint8)
    spr = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    spr.paste(Image.new("RGBA", (w, h), (255, 255, 255, 255)), (0, 0), mask(stroke + outline))
    spr.paste(Image.new("RGBA", (w, h), (0, 0, 0, 255)), (0, 0), mask(stroke))
    spr.paste(Image.fromarray(grad).convert("RGBA"), (0, 0), mask(0))
    return spr


def place(canvas, spr, cx, cy, scale, rot=0.0, alpha=1.0):
    if scale <= 0.03 or alpha <= 0:
        return
    s = spr.resize((max(1, int(spr.width * scale)), max(1, int(spr.height * scale))), Image.BILINEAR)
    if rot:
        s = s.rotate(rot, resample=Image.BILINEAR, expand=True)
    if alpha < 1:
        s.putalpha(s.getchannel("A").point(lambda v: int(v * alpha)))
    canvas.paste(s, (int(cx - s.width / 2), int(cy - s.height / 2)), s)


def pill(text, size=40, fg=(255, 255, 255), bg=(14, 14, 14, 220), accent=(230, 30, 30),
         padx=34, pady=16, dot=True):
    f = ImageFont.truetype(ARIAL_B, size)
    l, t, r, b = f.getbbox(text)
    dotw = 34 if dot else 0
    w, h = r - l + 2 * padx + dotw, b - t + 2 * pady + 8
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=h // 2, fill=bg, outline=accent, width=3)
    if dot:
        d.ellipse((padx - 4, h // 2 - 9, padx + 14, h // 2 + 9), fill=accent)
    d.text((padx + dotw - 4 - l, (h - (b - t)) // 2 - t), text, font=f, fill=fg)
    return img


def blend_rgba(frame, spr, x, y, op=1.0):
    arr = np.asarray(spr)
    h, w = arr.shape[:2]
    x0, y0, x1, y1 = max(0, x), max(0, y), min(W, x + w), min(H, y + h)
    if x1 <= x0 or y1 <= y0 or op <= 0:
        return
    sub = arr[y0 - y:y1 - y, x0 - x:x1 - x]
    a = sub[..., 3:4].astype(np.float32) / 255.0 * op
    reg = frame[y0:y1, x0:x1].astype(np.float32)
    frame[y0:y1, x0:x1] = (reg * (1 - a) + sub[..., :3] * a).astype(np.uint8)


# ---------------------------------------------------------------- logo cards
def logo_card(tagline=None, fade=0.0):
    glow = np.exp(-(R / 640.0) ** 2)
    base = np.array([17, 17, 17], np.float32)
    red = np.array([150, 18, 18], np.float32)
    arr = base + (red - base) * (glow * 0.5)[..., None]
    img = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
    logo = Image.open(LOGO).convert("RGBA").resize((600, 600), Image.LANCZOS)
    shadow = Image.new("RGBA", logo.size, (0, 0, 0, 0))
    shadow.putalpha(logo.getchannel("A").point(lambda v: int(v * 0.55)))
    from PIL import ImageFilter
    big = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    big.paste(shadow, (int(CX - 300), 150 + 24))
    big = big.filter(ImageFilter.GaussianBlur(28))
    img.paste(big, (0, 0), big)
    img.paste(logo, (int(CX - 300), 130), logo)
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(ARIAL_B, 104)
    word, track = "POCKET", 18
    widths = [f.getlength(c) for c in word]
    total = sum(widths) + track * (len(word) - 1)
    x = CX - total / 2
    for c, w_ in zip(word, widths):
        d.text((x, 748), c, font=f, fill=(244, 235, 214))
        x += w_ + track
    if tagline:
        f2 = ImageFont.truetype(ARIAL_B, 46)
        d.text((CX - f2.getlength(tagline) / 2, 905), tagline, font=f2, fill=(230, 60, 50))
    out = np.asarray(img).astype(np.float32)
    if fade > 0:
        out *= (1 - fade)
    return out.astype(np.uint8)


# ---------------------------------------------------------------- reveal (B)
def sunburst(t, dark, light, nrays, speed):
    rays = 0.5 + 0.5 * np.tanh(5 * np.sin(nrays * ANG + speed * t))
    fall = np.clip(1.25 - RN * 0.85, 0, 1)
    k = (rays * fall)[..., None]
    d, l = np.array(dark, np.float32), np.array(light, np.float32)
    return d + (l - d) * k


def add_ring(arr, r0, width, color, amp):
    if r0 <= 0 or r0 > 2500:
        return
    ring = np.exp(-((R - r0) / width) ** 2) * amp
    arr += ring[..., None] * np.array(color, np.float32)


def hsv(h):
    h %= 1.0
    i = int(h * 6)
    f = h * 6 - i
    q = [(1, f, 0), (1 - f, 1, 0), (0, 1, f), (0, 1 - f, 1), (f, 0, 1), (1, 0, 1 - f)][i % 6]
    return tuple(255 * c for c in q)


class Sparks:
    def __init__(self, n, seed, colors, speed=(500, 2200), life=(0.5, 1.3), delay=1.4, grav=700):
        r = random.Random(seed)
        self.p = [dict(a=r.uniform(0, 2 * math.pi), v=r.uniform(*speed), life=r.uniform(*life),
                       d=r.uniform(0, delay), c=r.choice(colors), w=r.choice([2, 3, 4, 5]))
                  for _ in range(n)]
        self.grav = grav

    def draw(self, d, u, origin=(CX, CY)):
        for p in self.p:
            k = u - p["d"]
            if k < 0 or k > p["life"]:
                continue
            def pos(k):
                return (origin[0] + math.cos(p["a"]) * p["v"] * k,
                        origin[1] + math.sin(p["a"]) * p["v"] * k + 0.5 * self.grav * k * k)
            x1, y1 = pos(k)
            x0, y0 = pos(max(0, k - 0.05))
            fade = 1 - k / p["life"]
            c = tuple(int(v * (0.35 + 0.65 * fade)) for v in p["c"])
            d.line((x0, y0, x1, y1), fill=c, width=p["w"])


def star(d, x, y, s, color):
    pts = [(x, y - s), (x + s * 0.18, y - s * 0.18), (x + s, y), (x + s * 0.18, y + s * 0.18),
           (x, y + s), (x - s * 0.18, y + s * 0.18), (x - s, y), (x - s * 0.18, y - s * 0.18)]
    d.polygon(pts, fill=color)


def bolt(d, rnd):
    x = rnd.uniform(300, W - 300)
    pts = [(x, 0)]
    y = 0
    while y < H:
        y += rnd.uniform(60, 130)
        x += rnd.uniform(-90, 90)
        pts.append((x, y))
    d.line(pts, fill=(140, 170, 255), width=18)
    d.line(pts, fill=(255, 255, 255), width=6)


BEAST = text_sprite("BEAST MODE", IMPACT, 300,
                    [(255, 250, 170), (255, 150, 0), (225, 20, 10)])
GOD = text_sprite("GOD MODE", IMPACT, 380,
                  [(255, 255, 255), (255, 214, 70), (214, 120, 0)], stroke=16, outline=12)
SUB1 = text_sprite("4x4 GRID  |  16 LIVE SCREENS", ARIAL_B, 62,
                   [(255, 255, 255), (255, 255, 255)], stroke=8, outline=0)
SUB2 = text_sprite("JUST TELL POCKET WHAT YOU WANT", ARIAL_B, 58,
                   [(255, 255, 255), (255, 235, 170)], stroke=8, outline=0)
STAMP = text_sprite("UNLOCKED", IMPACT, 130, [(255, 90, 80), (225, 20, 20), (170, 0, 0)],
                    stroke=8, outline=8)
SPARK_B = Sparks(150, 7, [(255, 200, 40), (255, 120, 10), (255, 240, 160), (255, 60, 20)])
SPARK_G = Sparks(170, 11, [(255, 255, 255), (255, 225, 110), (255, 190, 40)], delay=1.8, grav=250)
STAR_R = random.Random(3)
STARS = [(STAR_R.uniform(100, W - 100), STAR_R.uniform(80, H - 80), STAR_R.uniform(14, 44),
          STAR_R.uniform(0, 6)) for _ in range(34)]


def frame_B(i):
    t = i / FPS
    rnd = random.Random(i * 7919)
    flash = fry = glitch = bloom = 0.0
    ab, shake = 2.0, 0.0
    ops = []          # (sprite, cx, cy, scale, rot, alpha)
    sparks = None
    bolts = False
    stars_on = False

    if t < 0.55:
        pulse = 0.5 + 0.5 * math.sin(t * 16)
        rad = 160 + 420 * (t / 0.55)
        arr = np.exp(-(R / rad) ** 2)[..., None] * np.array([210, 20, 10], np.float32) * (0.25 + 0.35 * pulse)
        shake = 2 + 6 * t
    elif t < 3.4:
        u = t - 0.55
        v = max(0.0, (t - 3.0) / 0.4)
        arr = sunburst(t, (14, 0, 0), (255, 70, 10), 20, 3.0 + 4 * v) * (1 - v)
        arr += np.exp(-(R / 520.0) ** 2)[..., None] * np.array([255, 140, 20], np.float32) * 0.5 * (1 - v)
        s = 1 + 2.3 * math.exp(-u * 24) + 0.07 * math.sin(24 * u) * math.exp(-6 * u)
        if u > 0.4:
            s += 0.03 * math.sin(2 * math.pi * 2.5 * t)
        alpha = min(1.0, u / 0.04)
        shake = 45 * math.exp(-u * 5) + 5
        flash = 0.9 * math.exp(-u * 9)
        fry = math.exp(-u * 18)
        ab = 18 * math.exp(-u * 4) + 3
        if v > 0:
            s *= 1 + 1.2 * v * v
            alpha = 1 - v ** 2.5
            glitch, ab, shake = 1.0, 40 * v + 3, shake + 40 * v
        for k, d0 in enumerate((0.0, 0.18)):
            add_ring(arr, 2600 * (u - d0), 60 + 30 * k, (255, 190, 90), 1.1 - 0.4 * k)
        for k, e in enumerate((0.3, 0.15)):   # zoom echoes
            ops.append((BEAST, CX, CY - 60, s * (1 + 0.14 * (k + 1)), 0, alpha * e * (u > 0.1)))
        ops.append((BEAST, CX + rnd.uniform(-1, 1) * 4, CY - 60, s, rnd.uniform(-1.2, 1.2) * (1 + glitch * 3), alpha))
        if 0.8 < u and v == 0:
            ops.append((SUB1, CX, CY + 300, 0.55 + 0.45 * ease_out((u - 0.8) / 0.15), 0, 1))
        sparks = (SPARK_B, u)
    elif t < 5.66:
        prog = (t - 3.4) / 2.26
        arr = sunburst(t, (0, 0, 0), (255, 215, 90), 26, -1.5) * (prog ** 1.5 * 0.8)
        arr += np.exp(-(R / (30 + 520 * prog ** 2)) ** 2)[..., None] * np.array([255, 235, 170], np.float32) * (0.4 + 0.9 * prog)
        shake = 2 + 18 * prog ** 2
        ab = 2 + 10 * prog
        if t > 4.2 and rnd.random() < 0.35:
            bolts, flash = True, 0.18
    elif t < 7.55:
        u = t - 5.66
        arr = sunburst(t, (95, 45, 0), (255, 242, 175), 28, -2.0)
        arr += np.exp(-(R / 420.0) ** 2)[..., None] * 255 * 0.8
        s = 1 + 2.8 * math.exp(-u * 22) + 0.07 * math.sin(22 * u) * math.exp(-5 * u) \
            + 0.03 * math.sin(2 * math.pi * 2 * t)
        shake = 55 * math.exp(-u * 4) + 4
        flash = math.exp(-u * 7)
        fry = math.exp(-u * 15)
        bloom = 0.9
        ab = 24 * math.exp(-u * 4) + 3
        for k, d0 in enumerate((0.0, 0.12, 0.25)):
            add_ring(arr, 2700 * (u - d0), 70, hsv(u * 1.5 + k * 0.2), 0.9)
        for k, e in enumerate((0.3, 0.15)):
            ops.append((GOD, CX, CY - 40, s * (1 + 0.12 * (k + 1)), 0, min(1, u / 0.04) * e))
        ops.append((GOD, CX + rnd.uniform(-1, 1) * 3, CY - 40, s, rnd.uniform(-1, 1), min(1, u / 0.04)))
        if u > 0.7:
            su = u - 0.7
            ops.append((STAMP, CX + 470, CY + 190, 1 + 1.5 * math.exp(-su * 25), -9, 1))
            if su < 0.12:
                shake += 18
        if u > 1.0:
            ops.append((SUB2, CX, CY + 330, 0.55 + 0.45 * ease_out((u - 1.0) / 0.15), 0, 1))
        sparks = (SPARK_G, u)
        stars_on = True
    else:
        arr = np.full((H, W, 3), 255, np.float32)

    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    for spr, cx, cy, sc, rot, al in ops:
        place(img, spr, cx, cy, sc, rot, al)
    d = ImageDraw.Draw(img)
    if sparks:
        sparks[0].draw(d, sparks[1])
    if stars_on:
        for sx, sy, ss, ph in STARS:
            tw = abs(math.sin(t * 6 + ph))
            star(d, sx, sy, ss * tw, (255, 255, 235))
    if bolts:
        bolt(d, rnd)

    a = np.asarray(img).astype(np.float32)
    if fry > 0.02:
        a = (a - 128) * (1 + 0.9 * fry) + 128
        g = a.mean(axis=2, keepdims=True)
        a = g + (a - g) * (1 + 0.8 * fry)
    a = np.clip(a, 0, 255)
    if bloom:
        small = Image.fromarray(a.astype(np.uint8)).resize((W // 4, H // 4), Image.BILINEAR)
        from PIL import ImageFilter
        s_arr = np.clip(np.asarray(small).astype(np.float32) - 170, 0, 85) * 3
        bl = Image.fromarray(s_arr.astype(np.uint8)).filter(ImageFilter.GaussianBlur(14)).resize((W, H), Image.BILINEAR)
        a = np.clip(a + np.asarray(bl).astype(np.float32) * bloom, 0, 255)
    ab = int(ab)
    if ab:
        a[..., 0] = np.roll(a[..., 0], ab, axis=1)
        a[..., 2] = np.roll(a[..., 2], -ab, axis=1)
    if glitch:
        for _ in range(7):
            y0 = rnd.randint(0, H - 80)
            hh = rnd.randint(20, 90)
            a[y0:y0 + hh] = np.roll(a[y0:y0 + hh], rnd.randint(-160, 160), axis=1)
    a *= VIGNETTE
    if shake:
        a = np.roll(a, (int(rnd.uniform(-1, 1) * shake), int(rnd.uniform(-1, 1) * shake)), axis=(0, 1))
    if flash:
        a = a * (1 - min(1, flash)) + 255 * min(1, flash)
    if t >= 7.55:
        f = min(1.0, ((t - 7.55) / 0.45)) ** 1.5
        a = a * (1 - f) + 255 * f
    return np.clip(a, 0, 255).astype(np.uint8)


# ---------------------------------------------------------------- recording (C)
CAPTIONS = [
    (0.6, 6.4, "God Mode: just tell Pocket what you want", False),
    (6.8, 12.8, "Step 1: Log in with ChatGPT", False),
    (13.3, 17.8, "Pick your account, then click Continue", False),
    (19.0, 23.5, "Back in Pocket, ready to go", False),
    (24.3, 38.0, "Step 2: Type what you want", False),
    (39.2, 45.5, "Pocket opens 16 screens at once", False),
    (46.0, 56.5, "Watch them load, one by one", False),
    (57.6, 62.5, "16 live websites. One screen.", False),
    (63.2, 69.4, "BEAST MODE UNLOCKED", True),
]
CAP_SPR = {c[2]: pill(c[2].upper() if c[3] else c[2], size=46 if c[3] else 40,
                      bg=(225, 30, 30, 245) if c[3] else (14, 14, 14, 220),
                      accent=(255, 255, 255) if c[3] else (230, 30, 30), dot=not c[3])
           for c in CAPTIONS}
BADGE = pill("GOD MODE", size=34, fg=(30, 18, 0), bg=(255, 196, 40, 255), accent=(255, 255, 255),
             padx=26, pady=12, dot=False)


def overlay_C(frame, t):
    # badge pops in at 0.3s
    if t >= 0.3:
        k = (t - 0.3) / 0.4
        sc = 1.0 if k >= 1 else (ease_out(k) * 1.25 if k < 0.7 else 1.25 - 0.25 * ease_out((k - 0.7) / 0.3))
        spr = BADGE if sc == 1.0 else BADGE.resize((max(1, int(BADGE.width * sc)), max(1, int(BADGE.height * sc))), Image.BILINEAR)
        blend_rgba(frame, spr, W - 40 - spr.width, 24 + (BADGE.height - spr.height) // 2, 1.0)
    for a, b, text, big in CAPTIONS:
        if a <= t < b:
            fi, fo = ease_out((t - a) / 0.25), min(1.0, (b - t) / 0.2)
            spr = CAP_SPR[text]
            pulse = 1 + (0.05 * math.sin((t - a) * 9) if big else 0)
            if pulse != 1:
                spr = spr.resize((int(spr.width * pulse), int(spr.height * pulse)), Image.BILINEAR)
            x = (W - spr.width) // 2
            y = 960 + int(24 * (1 - fi)) - (spr.height - CAP_SPR[text].height) // 2
            blend_rgba(frame, spr, x, y, fi * fo)


def source_frames():
    cmd = ["ffmpeg", "-v", "error", "-i", SRC, "-an", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    n = W * H * 3
    while True:
        buf = p.stdout.read(n)
        if len(buf) < n:
            break
        yield np.frombuffer(buf, np.uint8).reshape(H, W, 3).copy()
    p.wait()


def frame_C(i, src):
    t = i / FPS
    overlay_C(src, t)
    if t < 0.5:
        f = (1 - t / 0.5) ** 2
        src = (src.astype(np.float32) * (1 - f) + 255 * f).astype(np.uint8)
    return src


# ---------------------------------------------------------------- main
def preview(specs):
    os.makedirs(PREV, exist_ok=True)
    cap = {}
    for s in specs:
        seg, ts = s.split(":")
        t = float(ts)
        i = int(t * FPS)
        if seg == "A":
            fr = logo_card()
        elif seg == "B":
            fr = frame_B(i)
        elif seg == "D":
            fr = logo_card("Your whole world, one screen.")
        else:
            sub = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(t), "-i", SRC, "-frames:v", "1",
                                  "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True).stdout
            fr = frame_C(i, np.frombuffer(sub, np.uint8).reshape(H, W, 3).copy())
        Image.fromarray(fr).save(f"{PREV}/{seg}_{ts}.png")
        print("wrote", f"{PREV}/{seg}_{ts}.png")


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    enc = subprocess.Popen(
        ["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
         "-r", str(FPS), "-i", "-", "-an", "-dn", "-map_metadata", "-1", "-c:v", "libx264",
         "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p", OUT], stdin=subprocess.PIPE)
    w = enc.stdin.write
    card = logo_card().tobytes()
    for _ in range(A_FR):
        w(card)
    print("A done", flush=True)
    for i in range(B_FR):
        w(frame_B(i).tobytes())
    print("B done", flush=True)
    n, last = 0, None
    for i, src in enumerate(source_frames()):
        last = src.copy()
        w(frame_C(i, src).tobytes())
        n += 1
    assert C_FR - 4 <= n <= C_FR, f"expected ~{C_FR} source frames, got {n}"
    for j in range(n, C_FR):      # source decodes a couple of frames short: hold the last frame
        w(frame_C(j, last.copy()).tobytes())
    print("C done", flush=True)
    for i in range(D_FR):
        fade = max(0.0, (i - (D_FR - 12)) / 12)
        w(logo_card("Your whole world, one screen.", fade).tobytes() if fade or i == 0 else dcard)
        if i == 0:
            dcard = logo_card("Your whole world, one screen.").tobytes()
    enc.stdin.close()
    enc.wait()
    print("done", OUT)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        preview(sys.argv[2:])
    else:
        main()
