#!/usr/bin/env python3
"""Refuses site pages that claim what the 2.0 build lacks.

    python3 -I site-deploy/check_site_claims.py <site dir> <scripts/check_store_copy.py>

Reads BANNED from the store copy check, so the site and the store listing are held
to one list. Checks the visible text and image alt text of every page except
privacy/, terms/, credits/ (they describe the code and its data) and join/.
"""
import importlib.util
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

SKIP = {"privacy", "terms", "credits", "join"}
EXTRA = {r"\bwhispers?\b": "Whisper is in ChirpCore only (Find uses it); nobody can whisper in 2.0"}


class Text(HTMLParser):
    def __init__(self):
        super().__init__()
        self.out, self.hidden = [], 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "svg"):
            self.hidden += 1
        for k, v in attrs:
            if k in ("alt", "aria-label", "content") and v:
                self.out.append(v)

    def handle_endtag(self, tag):
        if tag in ("script", "style", "svg"):
            self.hidden -= 1

    def handle_data(self, data):
        if not self.hidden:
            self.out.append(data)


def main(site: Path, store_check: Path) -> int:
    spec = importlib.util.spec_from_file_location("check_store_copy", store_check)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    banned = {**mod.BANNED, **EXTRA}
    problems = []
    for page in sorted(site.rglob("*.html")):
        rel = page.relative_to(site)
        if rel.parts[0] in SKIP:
            continue
        t = Text()
        t.feed(page.read_text(encoding="utf-8"))
        text = " ".join(t.out)
        for pattern, why in banned.items():
            m = re.search(pattern, text, re.IGNORECASE)
            if m:
                problems.append(f"{rel}: '{m.group(0)}' ({why})")
    for p in problems:
        print(p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2])))
