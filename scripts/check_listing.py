#!/usr/bin/env python3
"""Validate the fastlane-supply store listing in store/metadata against Play limits.

Checks every locale dir:
- title <= 30, short_description <= 80, full_description <= 4000, changelogs/*.txt <= 500
  characters (Play Console limits);
- images/icon.png is a 512x512 PNG (<= 1 MiB); images/featureGraphic.png is 1024x500 without
  alpha (<= 15 MiB);
- phone screenshots: 2..8 files, PNG without alpha, each side 320..3840 px, long side at most
  2x the short side, and at least 4 portrait shots of 1080x1920 or more (games are only
  promoted with those);
- Play metadata policy: no ranking / price / promotion words in the title ("free", "No.1", ...),
  no emoji anywhere;
- v2.0 content rules (docs/STORE_LISTING.md §2): no word that reveals the hidden form or that
  judges a child's drawing skill (SPEC §3.5, §10), nothing from v1 that is no longer true
  (turn-based battles, 30 stages, products for sale, "AI pictures cannot be imported").

Standard library only.

Usage: python3 scripts/check_listing.py [store/metadata]
"""
from __future__ import annotations

import re
import struct
import sys
from pathlib import Path

LIMITS = {"title.txt": 30, "short_description.txt": 80, "full_description.txt": 4000}
CHANGELOG_LIMIT = 500
MIN_SCREENSHOTS, MAX_SCREENSHOTS = 2, 8
MIN_PROMO_SCREENSHOTS = 4  # portrait >= 1080x1920, needed for game recommendations

# Play metadata policy: the title must not claim store performance, price or promotions.
TITLE_DENY = ["無料", "フリー", "free", "No.1", "No1", "ナンバーワン", "1位", "最高", "人気",
              "ランキング", "ベスト", "セール", "割引", "おすすめ", "新作", "NEW", "new", "top"]

# Never in any listing text (title, descriptions, release notes).
TEXT_DENY = {
    # The hidden form and internal scores are never mentioned publicly (SPEC §1, §3.5).
    "しょぼ": "hidden form (internal name)",
    "げいじゅつか": "hidden form (internal name)",
    "bloomer": "hidden form (internal name)",
    "大器晩成": "hidden form",
    "たいき": "hidden form",
    "隠し": "hidden form",
    "かくし": "hidden form",
    "子どもの絵らしさ": "internal score",
    "子どもらしさ": "internal score (judging the drawing)",
    "kid": "internal score",
    "上手さ": "judges the child's skill",
    "うまさ": "judges the child's skill",
    "上手すぎ": "judges the child's skill",
    "上手な絵": "judges the child's skill",
    "下手": "judges the child's skill",
    "点数": "judges the child's drawing",
    "採点": "judges the child's drawing",
    "AIで作": "AI-made pictures (hidden form)",
    "AI で作": "AI-made pictures (hidden form)",
    "AI画像": "AI-made pictures (hidden form)",
    "AI 画像": "AI-made pictures (hidden form)",
    "AIの絵": "AI-made pictures (hidden form)",
    "AI の絵": "AI-made pictures (hidden form)",
    "取り込めません": "v1: AI / digital pictures were rejected",
    "弱くな": "hints that some drawings become weak",
    "よわくな": "hints that some drawings become weak",
    # v1 facts that are no longer true in v2.0.
    "ターン制": "v1 battle (v2: real-time gauge battle)",
    "全30ステージ": "v1 stages (v2: 100)",
    "こうこくなしパス": "IAP is off in v2.0 (SPEC §10.2)",
    "フレームパック": "IAP is off in v2.0",
    "保存枠": "IAP is off in v2.0",
    "買い切り": "IAP is off in v2.0",
    "課金あり": "IAP is off in v2.0",
    "アプリ内課金・広告あり": "IAP is off in v2.0",
}

# Emoji and pictographs (Play: no excessive emoji; we use none).
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿️]")


def png_info(path: Path) -> tuple[int, int, int]:
    """(width, height, colour type) from the PNG IHDR chunk."""
    with path.open("rb") as fh:
        head = fh.read(29)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    w, h = struct.unpack(">II", head[16:24])
    return w, h, head[25]


def check_text(f: Path, text: str, errors: list[str]) -> None:
    for word, why in TEXT_DENY.items():
        if word in text:
            errors.append(f"{f}: must not contain '{word}' ({why})")
    m = EMOJI.search(text)
    if m:
        errors.append(f"{f}: emoji or pictograph '{m.group()}' (Play metadata policy)")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "store/metadata")
    errors: list[str] = []
    locales = [d for d in sorted(root.iterdir()) if d.is_dir()]
    if not locales:
        errors.append(f"no locale directories in {root}")
    for loc in locales:
        for name, limit in LIMITS.items():
            f = loc / name
            if not f.exists():
                errors.append(f"{f}: missing")
                continue
            text = f.read_text(encoding="utf-8").rstrip("\n")
            n = len(text)
            print(f"  {f}: {n}/{limit}")
            if n == 0 or n > limit:
                errors.append(f"{f}: {n} characters (1..{limit})")
            check_text(f, text, errors)
            if name == "title.txt":
                for word in TITLE_DENY:
                    if word in text:
                        errors.append(f"{f}: '{word}' in the title (Play metadata policy)")
        changelogs = sorted((loc / "changelogs").glob("*.txt"))
        if not changelogs:
            errors.append(f"{loc / 'changelogs'}: no release notes (default.txt)")
        for f in changelogs:
            text = f.read_text(encoding="utf-8").rstrip("\n")
            n = len(text)
            print(f"  {f}: {n}/{CHANGELOG_LIMIT}")
            if n == 0 or n > CHANGELOG_LIMIT:
                errors.append(f"{f}: {n} characters (1..{CHANGELOG_LIMIT})")
            check_text(f, text, errors)
        icon = loc / "images" / "icon.png"
        if icon.exists():
            w, h, ct = png_info(icon)
            if (w, h) != (512, 512) or icon.stat().st_size > 1 << 20:
                errors.append(f"{icon}: must be 512x512 PNG <= 1 MiB (is {w}x{h})")
        else:
            errors.append(f"{icon}: missing")
        fg = loc / "images" / "featureGraphic.png"
        if fg.exists():
            w, h, ct = png_info(fg)
            if (w, h) != (1024, 500) or ct in (4, 6) or fg.stat().st_size > 15 << 20:
                errors.append(f"{fg}: must be 1024x500 without alpha, <= 15 MiB "
                              f"(is {w}x{h}, colour type {ct})")
        else:
            errors.append(f"{fg}: missing")
        shots_dir = loc / "images" / "phoneScreenshots"
        shots = sorted(shots_dir.glob("*.png"))
        others = [p for p in sorted(shots_dir.glob("*")) if p.suffix.lower() != ".png"]
        for p in others:
            errors.append(f"{p}: phone screenshots must be PNG (compose_screenshots.py)")
        if not (MIN_SCREENSHOTS <= len(shots) <= MAX_SCREENSHOTS):
            errors.append(f"{shots_dir}: {len(shots)} screenshots "
                          f"({MIN_SCREENSHOTS}..{MAX_SCREENSHOTS})")
        promo = 0
        for shot in shots:
            w, h, ct = png_info(shot)
            print(f"  {shot.name}: {w}x{h}")
            if not (320 <= min(w, h) and max(w, h) <= 3840 and max(w, h) <= 2 * min(w, h)):
                errors.append(f"{shot}: {w}x{h} outside Play limits")
            if ct in (4, 6):
                errors.append(f"{shot}: has an alpha channel (Play: 24-bit PNG)")
            if h > w and w >= 1080 and h >= 1920:
                promo += 1
        if shots and promo < MIN_PROMO_SCREENSHOTS:
            errors.append(f"{shots_dir}: only {promo} portrait screenshots >= 1080x1920 "
                          f"(need {MIN_PROMO_SCREENSHOTS})")
    for e in errors:
        print(f"  FAIL {e}")
    print("check_listing: " + ("passed" if not errors else f"{len(errors)} error(s)"))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
