#!/usr/bin/env python3
"""Generate PLACEHOLDER store graphics and launcher-icon sources for おえかきファイターズ.

Outputs (all deterministic for a given SEED):
  store/metadata/ja-JP/images/icon.png          Play Store hi-res icon, 512x512, 32-bit PNG
  store/metadata/ja-JP/images/featureGraphic.png Play Store feature graphic, 1024x500, 24-bit PNG
  (fastlane supply layout; uploaded by `fastlane android metadata`)
  app/assets/launcher/icon-legacy.png         1024x1024 full icon (legacy launcher icon source)
  app/assets/launcher/icon-foreground.png     1024x1024 adaptive-icon foreground (safe zone)
  app/assets/launcher/icon-monochrome.png     1024x1024 Android 13+ themed-icon silhouette

The style is "crayon doodle": wobbly outlines with crayon grain, hatched colouring
that slightly misses the lines, like a child's drawing. These are placeholders the
owner can replace with real artwork (see docs/STORE_LISTING.md §graphics).

Font: Zen Maru Gothic Black (SIL OFL 1.1, store/fonts/OFL.txt). The TTF is not
committed; it is downloaded from a pinned google/fonts commit and verified.

Usage (from repo root):
  python3 -m pip install -r store/tools/requirements.txt
  python3 store/tools/gen_graphics.py
  (cd app && dart run flutter_launcher_icons)   # regenerates android mipmaps
"""
from __future__ import annotations

import hashlib
import math
import os
import random
import sys
import urllib.request
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SEED = 20261009
SS = 2  # supersampling factor

FONT_URL = (
    "https://raw.githubusercontent.com/google/fonts/"
    "2eb0b48d5f760f62e286216f0859a8c540dbc1bd/ofl/zenmarugothic/ZenMaruGothic-Black.ttf"
)
FONT_SHA256 = "6bd74fe76cd39ee0ec18775c3661d845343fb3f6f8fa09a3076638417baf741f"

PAPER = (255, 248, 231)
INK = (52, 44, 64)
ORANGE = (255, 140, 66)
ORANGE_DARK = (226, 92, 38)
BLUE = (88, 170, 255)
BLUE_DARK = (40, 110, 210)
YELLOW = (255, 214, 64)
PINK = (255, 150, 170)
GREEN = (120, 200, 110)
PURPLE = (170, 120, 230)


def font_path() -> Path:
    cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "doodle-battle-fonts"
    path = cache / "ZenMaruGothic-Black.ttf"
    if not path.exists():
        cache.mkdir(parents=True, exist_ok=True)
        data = urllib.request.urlopen(FONT_URL, timeout=60).read()
        if hashlib.sha256(data).hexdigest() != FONT_SHA256:
            sys.exit("font download: sha256 mismatch")
        path.write_bytes(data)
    return path


# --------------------------------------------------------------------------- crayon helpers
def noise(size: tuple[int, int], rng: random.Random, spread: float) -> Image.Image:
    """Seeded noise around 128 (Image.effect_noise is not seedable)."""
    raw = Image.frombytes("L", size, rng.randbytes(size[0] * size[1]))
    lo = int(128 - spread * 2)
    return raw.point(lambda v: max(0, min(255, lo + v * spread * 4 // 255)))


def grain(size: tuple[int, int], rng: random.Random, density: float = 0.78) -> Image.Image:
    """Alpha mask with crayon-like speckled gaps (L mode, 0..255)."""
    noise_img = noise(size, rng, 64).filter(ImageFilter.GaussianBlur(0.6))
    cut = int(128 + 64 * (1 - density) * 2 - 30)
    return noise_img.point(lambda v: 255 if v > cut - 40 else (150 if v > cut - 70 else 40))


def crayon_layer(size, draw_fn, color, rng, density=0.8, blur=0.4) -> Image.Image:
    """Draw with `draw_fn(ImageDraw)` in `color` on a transparent layer, then roughen it."""
    mask = Image.new("L", size, 0)
    draw_fn(ImageDraw.Draw(mask))
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(blur * SS))
    mask = ImageChops.multiply(mask, grain(size, rng, density))
    layer = Image.new("RGBA", size, color + (0,))
    layer.putalpha(mask)
    return layer


def wobble_path(points, rng, amp):
    return [(x + rng.uniform(-amp, amp), y + rng.uniform(-amp, amp)) for x, y in points]


def crayon_line(img, points, color, width, rng, passes=3, closed=False):
    size = img.size
    pts = list(points) + ([points[0]] if closed else [])

    def fn(d: ImageDraw.ImageDraw):
        for i in range(passes):
            w = max(1, int(width * rng.uniform(0.65, 1.0)))
            d.line(wobble_path(pts, rng, width * 0.18), fill=255, width=w, joint="curve")
            for p in pts[:: max(1, len(pts) // 12)]:
                r = w / 2
                d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=255)

    img.alpha_composite(crayon_layer(size, fn, color, rng, density=0.85, blur=0.3))


def crayon_fill(img, polygon, color, rng, hatch=10, angle=-35, spill=6):
    """Hatched colouring that roughly follows `polygon` and slightly spills over."""
    size = img.size
    shape = Image.new("L", size, 0)
    ImageDraw.Draw(shape).polygon(wobble_path(polygon, rng, spill), fill=255)
    shape = shape.filter(ImageFilter.MaxFilter(3))
    strokes = Image.new("L", size, 0)
    d = ImageDraw.Draw(strokes)
    xs = [p[0] for p in polygon]
    ys = [p[1] for p in polygon]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    span = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.6
    a = math.radians(angle)
    ux, uy = math.cos(a), math.sin(a)
    vx, vy = -uy, ux
    t = -span / 2
    while t < span / 2:
        x0, y0 = cx + vx * t - ux * span / 2, cy + vy * t - uy * span / 2
        x1, y1 = cx + vx * t + ux * span / 2, cy + vy * t + uy * span / 2
        d.line([(x0, y0), (x1, y1)], fill=rng.randint(200, 255), width=int(hatch * rng.uniform(0.9, 1.4)))
        t += hatch * rng.uniform(0.75, 1.05)
    mask = ImageChops.multiply(shape, strokes).filter(ImageFilter.GaussianBlur(0.8 * SS))
    mask = ImageChops.multiply(mask, grain(size, rng, 0.75))
    layer = Image.new("RGBA", size, color + (0,))
    layer.putalpha(mask)
    img.alpha_composite(layer)


def blob(cx, cy, r, rng, n=96, squash=1.0):
    p1, p2 = rng.uniform(0, 6.28), rng.uniform(0, 6.28)
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        rr = r * (1 + 0.05 * math.sin(3 * t + p1) + 0.035 * math.sin(5 * t + p2))
        pts.append((cx + rr * math.cos(t), cy + rr * math.sin(t) * squash))
    return pts


def star(cx, cy, r_out, r_in, points=5, rot=-90):
    pts = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        t = math.radians(rot + i * 180 / points)
        pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    return pts


# --------------------------------------------------------------------------- characters
def crayon_prop(img, x, y, length, angle_deg, color, rng, mono=False):
    """A crayon held like a little sword: body from (x, y) towards angle_deg
    (0 = right, 90 = up), pointed tip, paper wrapper band, ink outline."""
    a = math.radians(angle_deg)
    ux, uy = math.cos(a), -math.sin(a)
    vx, vy = -uy, ux
    hw = length * 0.16
    body_len = length * 0.74

    def at(t, w):
        return (x + ux * t + vx * w, y + uy * t + vy * w)

    body = [at(0, -hw), at(body_len, -hw), at(body_len, hw), at(0, hw)]
    tip = [at(body_len, -hw), at(length, 0), at(body_len, hw)]
    band = [at(body_len * 0.18, -hw), at(body_len * 0.45, -hw), at(body_len * 0.45, hw), at(body_len * 0.18, hw)]
    shape = [body[0], body[1], tip[1], body[2], body[3]]
    ink = (255, 255, 255) if mono else INK
    lw = max(2, length * 0.07)
    if mono:
        m = Image.new("L", img.size, 0)
        ImageDraw.Draw(m).polygon(shape, fill=255)
        layer = Image.new("RGBA", img.size, (255, 255, 255, 0))
        layer.putalpha(m)
        img.alpha_composite(layer)
    else:
        ImageDraw.Draw(img).polygon(shape, fill=color + (255,))
        crayon_fill(img, shape, tuple(max(0, c - 50) for c in color), rng, hatch=max(3, length * 0.05),
                    spill=0)
        ImageDraw.Draw(img).polygon(band, fill=(255, 255, 255, 255))
        crayon_line(img, band[1:3], ink, lw * 0.6, rng, passes=2)
        crayon_line(img, [band[3], band[0]], ink, lw * 0.6, rng, passes=2)
    crayon_line(img, body[:1] + tip[:1] + tip[1:2] + tip[2:] + body[3:], ink, lw, rng, closed=True)


def doodle_monster(img, cx, cy, r, body, body_dark, rng, facing=1, mono=False, prop=None):
    """A round crayon monster with horns, stubby arms, big eyes and a grin.
    With `prop` (a colour) it holds up a crayon like a sword in its raised hand."""
    line_w = max(3, int(r * 0.075))
    ink = (255, 255, 255) if mono else INK
    # horns
    for side in (-1, 1):
        hx = cx + side * r * 0.45
        horn = [(hx - r * 0.18, cy - r * 0.78), (hx + side * r * 0.08, cy - r * 1.22), (hx + r * 0.2, cy - r * 0.8)]
        if not mono:
            crayon_fill(img, horn, YELLOW, rng, hatch=max(4, r * 0.05), spill=r * 0.02)
        crayon_line(img, horn, ink, line_w * 0.8, rng, closed=True)
    # body
    shape = blob(cx, cy, r, rng, squash=0.95)
    if mono:
        m = Image.new("L", img.size, 0)
        ImageDraw.Draw(m).polygon(shape, fill=255)
        layer = Image.new("RGBA", img.size, (255, 255, 255, 0))
        layer.putalpha(m)
        img.alpha_composite(layer)
    else:
        crayon_fill(img, shape, body, rng, hatch=max(5, r * 0.06), spill=r * 0.03)
        belly = blob(cx + r * 0.05 * facing, cy + r * 0.35, r * 0.42, rng, squash=0.7)
        crayon_fill(img, belly, (255, 236, 200), rng, hatch=max(4, r * 0.045), angle=30, spill=r * 0.02)
        crayon_line(img, shape, body_dark, line_w * 0.6, rng, passes=1, closed=True)
    crayon_line(img, shape, ink, line_w, rng, closed=True)
    # arms (from the body outline outwards; one waves up, one points forward)
    for side in (-1, 1):
        ax = cx + side * r * 0.97
        lift = 0.32 if side == facing else 0.12
        arm = [(ax, cy + r * 0.05), (ax + side * r * 0.24, cy - r * lift * 0.5),
               (ax + side * r * 0.34, cy - r * lift)]
        crayon_line(img, arm, ink, line_w, rng)
        if prop is not None and side == facing:
            # held upright, leaning a little inwards (stays inside the adaptive-icon safe zone)
            crayon_prop(img, arm[-1][0] - side * r * 0.1, arm[-1][1] + r * 0.14, r * 0.66,
                        90 + side * 12, prop, rng, mono=mono)
    if mono:
        return
    # eyes
    for side in (-1, 1):
        ex, ey = cx + side * r * 0.3 + facing * r * 0.06, cy - r * 0.18
        er = r * 0.2
        d = ImageDraw.Draw(img)
        d.ellipse((ex - er, ey - er * 1.1, ex + er, ey + er * 1.1), fill=(255, 255, 255, 255))
        crayon_line(img, blob(ex, ey, er, rng, n=40, squash=1.1), INK, line_w * 0.6, rng, passes=2, closed=True)
        pr = er * 0.5
        px = ex + facing * er * 0.3
        d.ellipse((px - pr, ey - pr * 0.9, px + pr, ey + pr * 1.1), fill=INK + (255,))
        d.ellipse((px - pr * 0.2, ey - pr * 0.6, px + pr * 0.25, ey - pr * 0.15), fill=(255, 255, 255, 255))
    # cheeks
    for side in (-1, 1):
        ch = blob(cx + side * r * 0.58 + facing * r * 0.04, cy + r * 0.12, r * 0.11, rng, n=30, squash=0.7)
        crayon_fill(img, ch, PINK, rng, hatch=max(3, r * 0.03), spill=1)
    # grin
    mx = cx + facing * r * 0.05
    mouth = [(mx - r * 0.3 + i * r * 0.6 / 16, cy + r * 0.12 + math.sin(i / 16 * math.pi) * r * 0.22) for i in range(17)]
    crayon_line(img, mouth, INK, line_w, rng)
    fang = [(mx - r * 0.12, cy + r * 0.2), (mx - r * 0.06, cy + r * 0.3), (mx, cy + r * 0.21)]
    ImageDraw.Draw(img).polygon(fang, fill=(255, 255, 255, 255))


def sparkles(img, rng, boxes, colors, count, size_range):
    for _ in range(count):
        x0, y0, x1, y1 = rng.choice(boxes)
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        s = rng.uniform(*size_range)
        col = rng.choice(colors)
        if rng.random() < 0.6:
            pts = star(x, y, s, s * 0.45, rot=rng.uniform(-110, -70))
            crayon_fill(img, pts, col, rng, hatch=max(3, s * 0.18), spill=1)
            crayon_line(img, pts, col, max(2, s * 0.12), rng, passes=2, closed=True)
        else:
            # little "pop" burst: short dashes radiating from a centre
            for k in range(5):
                a = math.radians(k * 72 + rng.uniform(-12, 12))
                p0 = (x + math.cos(a) * s * 0.45, y + math.sin(a) * s * 0.45)
                p1 = (x + math.cos(a) * s, y + math.sin(a) * s)
                crayon_line(img, [p0, p1], col, max(2, s * 0.13), rng, passes=2)


def paper(size, rng):
    img = Image.new("RGBA", size, PAPER + (255,))
    tex = noise(size, rng, 18).filter(ImageFilter.GaussianBlur(1.2 * SS))
    shade = Image.new("RGBA", size, (190, 170, 130, 0))
    shade.putalpha(tex.point(lambda v: max(0, v - 128) // 3))
    img.alpha_composite(shade)
    return img


def scribble_bg(img, rng, colors, count):
    w, h = img.size
    for _ in range(count):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        col = rng.choice(colors)
        pts = []
        a = rng.uniform(0, 6.28)
        for i in range(14):
            a += rng.uniform(-0.9, 0.9)
            x += math.cos(a) * w * 0.012
            y += math.sin(a) * w * 0.012
            pts.append((x, y))
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        crayon_line(layer, pts, col, w * 0.006, rng, passes=2)
        layer.putalpha(layer.getchannel("A").point(lambda v: v * 45 // 100))
        img.alpha_composite(layer)


# --------------------------------------------------------------------------- outputs
def make_icon(px: int) -> Image.Image:
    rng = random.Random(SEED)
    s = px * SS
    img = paper((s, s), rng)
    sparkles(img, rng, [(s * 0.06, s * 0.06, s * 0.3, s * 0.3), (s * 0.72, s * 0.08, s * 0.94, s * 0.28)],
             [YELLOW, BLUE, GREEN, PINK], 4, (s * 0.04, s * 0.07))
    doodle_monster(img, s * 0.5, s * 0.56, s * 0.32, ORANGE, ORANGE_DARK, rng, prop=BLUE)
    return img.resize((px, px), Image.LANCZOS)


def make_foreground(px: int, mono=False) -> Image.Image:
    rng = random.Random(SEED)
    s = px * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    # adaptive icons: 108dp canvas, ~66dp guaranteed visible circle -> keep within r ~ 0.30*s
    doodle_monster(img, s * 0.5, s * 0.54, s * 0.215, ORANGE, ORANGE_DARK, rng, mono=mono, prop=BLUE)
    if not mono:
        sparkles(img, rng, [(s * 0.27, s * 0.27, s * 0.36, s * 0.36), (s * 0.64, s * 0.28, s * 0.72, s * 0.36)],
                 [YELLOW, BLUE], 2, (s * 0.025, s * 0.04))
    return img.resize((px, px), Image.LANCZOS)


def outlined_text(img, xy, text, font, fill, outline, width, rng):
    d = ImageDraw.Draw(img)
    x, y = xy
    # crayon outline: several jittered strokes
    for _ in range(3):
        jx, jy = rng.uniform(-width * 0.15, width * 0.15), rng.uniform(-width * 0.15, width * 0.15)
        d.text((x + jx, y + jy), text, font=font, fill=outline + (255,), stroke_width=int(width), stroke_fill=outline + (255,))
    d.text((x, y), text, font=font, fill=fill + (255,))


def make_feature() -> Image.Image:
    rng = random.Random(SEED + 1)
    W, H = 1024 * SS, 500 * SS
    img = paper((W, H), rng)
    scribble_bg(img, rng, [YELLOW, BLUE, GREEN, PINK, PURPLE], 26)
    # two crayon fighters facing each other
    doodle_monster(img, W * 0.135, H * 0.64, H * 0.19, ORANGE, ORANGE_DARK, rng, facing=1, prop=BLUE)
    doodle_monster(img, W * 0.865, H * 0.64, H * 0.19, BLUE, BLUE_DARK, rng, facing=-1, prop=PINK)
    sparkles(img, rng, [(W * 0.3, H * 0.03, W * 0.7, H * 0.12), (W * 0.32, H * 0.84, W * 0.68, H * 0.95)],
             [YELLOW, PINK, GREEN, PURPLE], 9, (H * 0.03, H * 0.05))
    fp = str(font_path())
    d = ImageDraw.Draw(img)
    # app name on two lines: small 「おえかき」 over a big 「ファイターズ」
    top, main_title = "おえかき", "ファイターズ"
    f_top = ImageFont.truetype(fp, int(H * 0.105))
    f = ImageFont.truetype(fp, int(H * 0.165))
    bt = d.textbbox((0, 0), top, font=f_top)
    bb = d.textbbox((0, 0), main_title, font=f)
    ty_top = H * 0.14 - bt[1]
    outlined_text(img, ((W - (bt[2] - bt[0])) / 2 - bt[0], ty_top), top, f_top, (255, 255, 255), BLUE_DARK,
                  H * 0.018, rng)
    tw = bb[2] - bb[0]
    tx, ty = (W - tw) / 2 - bb[0], ty_top + bt[3] + H * 0.035 - bb[1]
    outlined_text(img, (tx, ty), main_title, f, (255, 255, 255), ORANGE_DARK, H * 0.022, rng)
    # crayon underline
    crayon_line(img, [(W * 0.34 + i * W * 0.32 / 20, ty + bb[3] + H * 0.045 + math.sin(i / 2.0) * H * 0.008)
                      for i in range(21)], YELLOW, H * 0.02, rng)
    sub = "かいた えが うごいて たたかう！"
    f2 = ImageFont.truetype(fp, int(H * 0.058))
    bb2 = d.textbbox((0, 0), sub, font=f2)
    sx = (W - (bb2[2] - bb2[0])) / 2 - bb2[0]
    sy = ty + bb[3] + H * 0.105
    outlined_text(img, (sx, sy), sub, f2, INK, (255, 255, 255), H * 0.012, rng)
    return img.resize((1024, 500), Image.LANCZOS).convert("RGB")


def main() -> None:
    out_store = ROOT / "store" / "metadata" / "ja-JP" / "images"
    out_launcher = ROOT / "app" / "assets" / "launcher"
    out_store.mkdir(parents=True, exist_ok=True)
    out_launcher.mkdir(parents=True, exist_ok=True)

    make_icon(512).save(out_store / "icon.png", optimize=True)
    make_feature().save(out_store / "featureGraphic.png", optimize=True)
    make_icon(1024).convert("RGB").save(out_launcher / "icon-legacy.png", optimize=True)
    make_foreground(1024).save(out_launcher / "icon-foreground.png", optimize=True)
    make_foreground(1024, mono=True).save(out_launcher / "icon-monochrome.png", optimize=True)
    for p in sorted(list(out_store.glob("*.png")) + list(out_launcher.glob("*.png"))):
        with Image.open(p) as im:
            print(f"{p.relative_to(ROOT)}  {im.size[0]}x{im.size[1]} {im.mode}  {p.stat().st_size // 1024} KiB")


if __name__ == "__main__":
    main()
