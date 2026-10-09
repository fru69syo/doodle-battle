#!/usr/bin/env python3
"""Check and render the static policy site (site/) for GitHub Pages.

  python3 scripts/build_site.py --check                    # lint only (CI)
  python3 scripts/build_site.py --out _site \\
      --var DEVELOPER_NAME=... --var SUPPORT_EMAIL=... --var ADMOB_PUBLISHER_ID=pub-...

Checks (fail = exit 1):
  - every page: <html lang="ja">, charset, viewport, <title>
  - no <script>, no external stylesheets/images/iframes (kids' policy pages: no trackers)
  - internal links point to existing files and #anchors to existing ids
  - only the known {{PLACEHOLDERS}} are used; with --out every one must be given a valid
    value and none may remain in the output
The pages the app opens (app/lib/core/config/app_config.dart PolicyPage) must exist.
"""
import argparse
import html.parser
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
APP_PAGES = ["index.html", "privacy.html", "terms.html", "delete.html"]
PLACEHOLDERS = {
    "DEVELOPER_NAME": re.compile(r"^\S.{0,79}$"),
    "SUPPORT_EMAIL": re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"),
    "ADMOB_PUBLISHER_ID": re.compile(r"^pub-\d{16}$"),
}
PH = re.compile(r"\{\{([A-Z_]+)\}\}")


class Page(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.lang = None
        self.charset = self.viewport = self.title = False
        self.ids = set()
        self.links = []
        self.problems = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.add(a["id"])
        if tag == "html":
            self.lang = a.get("lang")
        elif tag == "meta":
            self.charset |= "charset" in a
            self.viewport |= a.get("name") == "viewport"
        elif tag == "title":
            self.title = True
        elif tag == "script":
            self.problems.append("<script> is not allowed")
        elif tag in ("img", "iframe", "video", "audio", "source", "embed", "object"):
            src = a.get("src", "")
            if re.match(r"^(https?:)?//", src):
                self.problems.append(f"external <{tag} src={src}>")
        elif tag == "link":
            href = a.get("href", "")
            if re.match(r"^(https?:)?//", href):
                self.problems.append(f"external <link href={href}>")
        if tag == "a" and "href" in a:
            self.links.append(a["href"])


def check(site: Path) -> list[str]:
    errors = []
    pages = {}
    for f in sorted(site.glob("*.html")):
        p = Page()
        p.feed(f.read_text(encoding="utf-8"))
        pages[f.name] = p
        if p.lang != "ja":
            errors.append(f"{f.name}: <html lang=\"ja\"> missing")
        if not (p.charset and p.viewport and p.title):
            errors.append(f"{f.name}: needs <meta charset>, viewport meta and <title>")
        errors += [f"{f.name}: {m}" for m in p.problems]
    for name in APP_PAGES:
        if name not in pages:
            errors.append(f"{name}: missing (opened by the app, PolicyPage)")
    for name, p in pages.items():
        for href in p.links:
            if re.match(r"^(https?:|mailto:)", href):
                continue
            target, _, anchor = href.partition("#")
            target = target or name
            if target not in pages:
                errors.append(f"{name}: broken link {href}")
            elif anchor and anchor not in pages[target].ids:
                errors.append(f"{name}: missing anchor {href}")
    for f in sorted(site.iterdir()):
        if f.is_file():
            for ph in PH.findall(f.read_text(encoding="utf-8")):
                if ph not in PLACEHOLDERS:
                    errors.append(f"{f.name}: unknown placeholder {{{{{ph}}}}}")
    return errors


def render(site: Path, out: Path, values: dict[str, str]) -> list[str]:
    errors = []
    for k, rx in PLACEHOLDERS.items():
        v = values.get(k, "")
        if not rx.match(v):
            errors.append(f"--var {k} is missing or invalid ({v!r})")
    if errors:
        return errors
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    for f in sorted(site.iterdir()):
        if not f.is_file():
            continue
        text = f.read_text(encoding="utf-8")
        text = PH.sub(lambda m: values[m.group(1)], text)
        (out / f.name).write_text(text, encoding="utf-8")
        if PH.search(text):
            errors.append(f"{f.name}: placeholder left after rendering")
    (out / ".nojekyll").write_text("", encoding="utf-8")
    return errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--out")
    ap.add_argument("--var", action="append", default=[], metavar="KEY=VALUE")
    args = ap.parse_args()
    errors = check(SITE)
    if args.out and not errors:
        values = dict(v.split("=", 1) for v in args.var if "=" in v)
        errors += render(SITE, Path(args.out), values)
    for e in errors:
        print(f"FAIL {e}")
    if errors:
        return 1
    print("site: ok" + (f" (rendered to {args.out})" if args.out else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
