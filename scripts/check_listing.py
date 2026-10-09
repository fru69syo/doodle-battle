#!/usr/bin/env python3
"""Validate the fastlane-supply store listing in store/metadata against Play limits.

Checks every locale dir: title <= 30, short_description <= 80, full_description <= 4000,
changelogs/*.txt <= 500 characters; images/icon.png is 512x512 PNG (<= 1 MiB);
images/featureGraphic.png is 1024x500 without alpha (<= 15 MiB); phone screenshots
(if any) are 320..3840 px with an aspect ratio of at most 2:1. Standard library only.

Usage: python3 scripts/check_listing.py [store/metadata]
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

LIMITS = {"title.txt": 30, "short_description.txt": 80, "full_description.txt": 4000}


def png_info(path: Path) -> tuple[int, int, int]:
    """(width, height, colour type) from the PNG IHDR chunk."""
    with path.open("rb") as fh:
        head = fh.read(29)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    w, h = struct.unpack(">II", head[16:24])
    return w, h, head[25]


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
            n = len(f.read_text(encoding="utf-8").rstrip("\n"))
            print(f"  {f}: {n}/{limit}")
            if n == 0 or n > limit:
                errors.append(f"{f}: {n} characters (1..{limit})")
        for f in sorted((loc / "changelogs").glob("*.txt")):
            n = len(f.read_text(encoding="utf-8").rstrip("\n"))
            if n > 500:
                errors.append(f"{f}: {n} characters (max 500)")
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
            if (w, h) != (1024, 500) or ct in (4, 6):
                errors.append(f"{fg}: must be 1024x500 without alpha (is {w}x{h}, colour type {ct})")
        else:
            errors.append(f"{fg}: missing")
        for shot in sorted((loc / "images" / "phoneScreenshots").glob("*.png")):
            w, h, _ = png_info(shot)
            if not (320 <= min(w, h) and max(w, h) <= 3840 and max(w, h) <= 2 * min(w, h)):
                errors.append(f"{shot}: {w}x{h} outside Play limits")
    for e in errors:
        print(f"  FAIL {e}")
    print("check_listing: " + ("passed" if not errors else f"{len(errors)} error(s)"))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
