#!/usr/bin/env python3
"""Compose the Play Store phone screenshots from the raw app screenshots.

Input:  store/screenshots/raw/*.png (+ 00_paper_photo.jpg), rendered from the real
        app by app/tool/screenshots.sh (test/screenshots/screenshots_test.dart).
Output: store/metadata/ja-JP/images/phoneScreenshots/NN_<name>.png  (1080x1920, RGB;
        the first 8, Play's limit for phone screenshots)
        store/screenshots/alternates/NN_<name>.png                    (the rest, to swap in)
        store/screenshots/contact_sheet.png                          (listing + raw)

Each listing image is the unmodified app screen, scaled down, under a short caption.
Shot 1 puts the photographed paper drawing next to the birth screen of the same
drawing (Before/After). The parent-safety shot lists only things the app really does
(docs/STORE_LISTING.md §2, QA_CHECKLIST). No other app is named anywhere, and no shot
shows the hidden form or anything that rates a drawing (SPEC §3.5).

Usage (from repo root, after app/tool/screenshots.sh):
  python3 store/tools/compose_screenshots.py
"""
from __future__ import annotations

import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.dont_write_bytecode = True  # no __pycache__ in store/tools
sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_graphics as g  # noqa: E402  (crayon helpers + pinned font)

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "store" / "screenshots" / "raw"
OUT = ROOT / "store" / "metadata" / "ja-JP" / "images" / "phoneScreenshots"
ALTERNATES = ROOT / "store" / "screenshots" / "alternates"
SHEET = ROOT / "store" / "screenshots" / "contact_sheet.png"
PLAY_MAX_PHONE_SCREENSHOTS = 8
W, H = 1080, 1920

ORANGE = (255, 122, 47)
BLUE = (47, 128, 237)
GREEN = (52, 168, 83)
PINK = (233, 64, 145)
PURPLE = (124, 77, 255)
TEAL = (0, 150, 136)
RED = (229, 57, 53)

# (output name, raw screen, caption lines, band colour)
# v2.0 order (docs/STORE_LISTING.md §3): what makes the app different first.
# Never a screen that shows the hidden form or rates a drawing (the raw shots
# only contain kid drawings, screenshots_test.dart checks it).
LISTING = [
    ("01_before_after", "05_birth_traits", ["かいた えが", "うごく キャラに！"], ORANGE),
    ("02_battle", "10_battle", ["わざを えらぶだけ！", "リアルタイム バトル"], BLUE),
    ("03_draw", "03b_draw_canvas", ["アプリの なかでも", "おえかき できる"], GREEN),
    ("04_joints", "08c_joint_editor", ["うごく ところを", "じぶんで なおせる"], PURPLE),
    ("05_stages", "09b_stage_select", ["ぜんぶで", "100 ステージ！"], RED),
    ("06_online", "13_online_lobby", ["バッジが そだつ", "オンライン たいせん"], BLUE),
    ("07_family", "19_family_battle", ["かぞくで", "たいせん できる"], PINK),
    ("08_parents", "15_parent_settings", ["おうちの かたへ", "あんしんの しくみ"], TEAL),
    ("09_video", "22_video_export", ["うごく どうがに", "できる"], PURPLE),
    ("10_card", "20_card_print", ["カードに して", "いんさつ"], RED),
    ("11_odai", "21_odai_calendar", ["まいにちの おだいで", "おえかき"], GREEN),
    ("12_grow", "08_character_detail", ["そだてて", "しんか！"], ORANGE),
    ("13_capture", "04_capture_guide", ["とりかたの コツも", "おしえるよ"], BLUE),
    ("14_zukan", "07_zukan", ["ずかんに", "あつめよう"], PINK),
]

# Shown on 08_parents. Each line is backed by the implementation (QA_CHECKLIST
# §13.3) and by the v2.0 spec (SPEC §7.2, §10). No "paper drawings only" any
# more: v2.0 accepts every picture that is not a photo or unsafe.
SAFETY = [
    "チャットなし・ガチャなし",
    "無料・アプリ内課金なし",
    "設定と外部リンクは 保護者の確認の先",
    "広告・オンラインは 初期設定でオフ",
    "絵は AI の学習に使いません",
]


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(g.font_path()), size)


def background(color, rng) -> Image.Image:
    img = g.paper((W, H), rng)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((-40, -40, W + 40, 330), radius=80, fill=color + (255,))
    # a few crayon squiggles on the band
    g.scribble_bg(img, rng, [(255, 255, 255)], 6)
    return img


def caption(img, lines, rng, top=40):
    f = font(92)
    y = top
    for line in lines:
        bb = ImageDraw.Draw(img).textbbox((0, 0), line, font=f)
        x = (W - (bb[2] - bb[0])) / 2 - bb[0]
        g.outlined_text(img, (x, y - bb[1]), line, f, (255, 255, 255), g.INK, 9, rng)
        y += 120


def rounded(im: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.size[0] - 1, im.size[1] - 1), radius=radius, fill=255)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def paste_with_shadow(img, im, xy, blur=18, offset=(0, 14)):
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    a = Image.new("RGBA", im.size, (40, 30, 50, 110))
    a.putalpha(im.getchannel("A").point(lambda v: v * 110 // 255))
    shadow.alpha_composite(a, (xy[0] + offset[0], xy[1] + offset[1]))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))
    img.alpha_composite(im, xy)


def phone(raw: Image.Image, width: int) -> Image.Image:
    h = round(raw.size[1] * width / raw.size[0])
    framed = Image.new("RGBA", (width + 24, h + 24), g.INK + (255,))
    framed = rounded(framed, 48)
    framed.alpha_composite(rounded(raw.convert("RGB").resize((width, h), Image.LANCZOS), 38), (12, 12))
    return framed


def standard(name, raw_name, lines, color, rng) -> Image.Image:
    img = background(color, rng)
    caption(img, lines, rng)
    shot = phone(Image.open(RAW / f"{raw_name}.png"), 860)
    paste_with_shadow(img, shot, ((W - shot.size[0]) // 2, 380))
    return img


def label(img, text, center, size=46):
    f = font(size)
    d = ImageDraw.Draw(img)
    bb = d.textbbox((0, 0), text, font=f)
    tw = bb[2] - bb[0]
    cx, cy = center
    d.rounded_rectangle((cx - tw / 2 - 24, cy - size * 0.85, cx + tw / 2 + 24, cy + size * 0.85), radius=40,
                        fill=(255, 255, 255, 255), outline=g.INK + (255,), width=5)
    d.text((cx - tw / 2 - bb[0], cy - (bb[1] + bb[3]) / 2), text, font=f, fill=g.INK + (255,))


def before_after(lines, color, rng) -> Image.Image:
    img = background(color, rng)
    caption(img, lines, rng)
    shot = phone(Image.open(RAW / "05_birth_traits.png"), 660)
    sx = W - shot.size[0] - 28
    paste_with_shadow(img, shot, (sx, 380))
    # the photographed paper drawing, like a print lying on the table
    photo = Image.open(RAW / "00_paper_photo.jpg").convert("RGB")
    pw = 300
    photo = photo.resize((pw, round(photo.size[1] * pw / photo.size[0])), Image.LANCZOS)
    card = Image.new("RGBA", (photo.size[0] + 24, photo.size[1] + 24), (255, 255, 255, 255))
    card.alpha_composite(photo.convert("RGBA"), (12, 12))
    card = card.rotate(6, resample=Image.BICUBIC, expand=True)
    paste_with_shadow(img, card, (14, 470), blur=14, offset=(6, 12))
    label(img, "かいた え", (190, 1010))
    # crayon arrow from the paper to the new character
    ay = 1120
    g.crayon_line(img, [(110 + i * 14, ay + math.sin(i / 3) * 8) for i in range(17)], g.ORANGE_DARK, 24, rng)
    g.crayon_line(img, [(300, ay - 45), (352, ay), (300, ay + 45)], g.ORANGE_DARK, 24, rng)
    label(img, "かみに かいて とるだけ。アプリでも かけるよ", (W / 2, 1820), size=42)
    return img


def parents(lines, color, rng) -> Image.Image:
    img = background(color, rng)
    caption(img, lines, rng)
    shot = phone(Image.open(RAW / "15_parent_settings.png"), 640)
    paste_with_shadow(img, shot, ((W - shot.size[0]) // 2, 980))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((50, 410, W - 50, 940), radius=44, fill=(255, 255, 255, 255),
                        outline=color + (255,), width=8)
    f = font(46)
    y = 448
    for item in SAFETY:
        d.ellipse((90, y + 8, 134, y + 52), fill=color + (255,))
        d.line([(101, y + 30), (110, y + 40), (124, y + 20)], fill=(255, 255, 255, 255), width=7)
        size = 46
        while ImageDraw.Draw(img).textlength(item, font=font(size)) > W - 230 and size > 30:
            size -= 2
        d.text((156, y + 30), item, font=font(size), fill=g.INK + (255,), anchor="lm")
        y += 98
    return img


def contact_sheet(listing: list[Path]) -> None:
    raws = sorted(RAW.glob("*.png"))
    tw, th, pad = 216, 384, 16
    cols = 8
    label_h = 34
    rows_raw = math.ceil(len(raws) / cols)
    rows_listing = math.ceil(len(listing) / cols)
    title_h = 90
    sheet_h = title_h * 2 + (rows_raw + rows_listing) * (th + label_h + pad) + pad
    sheet = Image.new("RGB", (cols * (tw + pad) + pad, sheet_h), (250, 246, 236))
    d = ImageDraw.Draw(sheet)
    f_title, f_label = font(44), ImageFont.truetype(str(g.font_path()), 18)
    y = 20
    for title, files in (("ストア用（1〜8: phoneScreenshots、9〜: alternates）", listing),
                         ("アプリの画面（raw）", raws)):
        d.text((pad, y), title, font=f_title, fill=g.INK)
        y += title_h - 20
        for i, p in enumerate(files):
            x = pad + (i % cols) * (tw + pad)
            yy = y + (i // cols) * (th + label_h + pad)
            sheet.paste(Image.open(p).convert("RGB").resize((tw, th), Image.LANCZOS), (x, yy))
            d.text((x, yy + th + 6), p.stem, font=f_label, fill=g.INK)
        y += math.ceil(len(files) / cols) * (th + label_h + pad) + 20
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(SHEET, optimize=True)


def main() -> None:
    for d in (OUT, ALTERNATES):
        d.mkdir(parents=True, exist_ok=True)
        for old in d.glob("*.png"):
            old.unlink()
    written = []
    for i, (name, raw_name, lines, color) in enumerate(LISTING):
        rng = random.Random(g.SEED + 100 + i)
        if name == "01_before_after":
            img = before_after(lines, color, rng)
        elif name == "08_parents":
            img = parents(lines, color, rng)
        else:
            img = standard(name, raw_name, lines, color, rng)
        path = (OUT if i < PLAY_MAX_PHONE_SCREENSHOTS else ALTERNATES) / f"{name}.png"
        img.convert("RGB").save(path, optimize=True)
        written.append(path)
        print(f"{path.relative_to(ROOT)}  ← {raw_name}")
    contact_sheet(written)
    print(f"{SHEET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
