#!/usr/bin/env python3
"""Check the App Store copy in fastlane/metadata/en-US (HARD RULE part 5, docs/NEXT.md).

Fails on: App Store length limits, any em dash (house rule for user-facing copy),
and words for things 2.0 does not do. 1.0's copy claimed a map, voice messages,
photo sharing and "mesh" relay hops; 2.0 has none of them in the app, so a claim
of one is a claim the build cannot keep. When a feature lands in the app, take its
word off BANNED in the same change.

    python3 scripts/check_store_copy.py [metadata_dir]
"""
import re
import sys
from pathlib import Path

LIMITS = {  # characters, from App Store Connect; keywords are counted in bytes
    "name.txt": 30,
    "subtitle.txt": 30,
    "promotional_text.txt": 170,
    "description.txt": 4000,
    "release_notes.txt": 4000,
    "keywords.txt": 100,
}

# word -> why it is not allowed (what 2.0's app lacks)
BANNED = {
    r"\bmaps?\b": "2.0 has no map",
    r"\bphotos?\b": "photos are in ChirpCore only, not in the app",
    r"\bvoice messages?\b": "2.0 has no recorded voice messages",
    r"\bmesh\b": "plain words only (Dawn Chorus spec), and no relay is promised",
    r"\bhops?\b": "no relay range is promised",
    r"\bmeet-?up\b": "Meet-up is a design screen, not wired in the app yet",
    r"\bcatch up\b": "Catch up has no screen in real use yet",
    r"\bbattery\b": "battery is not shown in the app",
    r"\bwatch\b": "Apple Watch is 2.1",
    r"\btranslat": "translation is 2.1",
    r"\bAES\b|\b256\b": "no cipher claims in store copy",
}


def check(root: Path) -> list[str]:
    problems = []
    for name, limit in LIMITS.items():
        path = root / name
        if not path.exists():
            problems.append(f"{name}: missing")
            continue
        text = path.read_text(encoding="utf-8").strip()
        size = len(text.encode("utf-8")) if name == "keywords.txt" else len(text)
        if size > limit:
            problems.append(f"{name}: {size} over the limit of {limit}")
        if "—" in text:
            problems.append(f"{name}: em dash")
        for pattern, why in BANNED.items():
            m = re.search(pattern, text, re.IGNORECASE)
            if m:
                problems.append(f"{name}: '{m.group(0)}' ({why})")
    kw = (root / "keywords.txt")
    if kw.exists() and ", " in kw.read_text(encoding="utf-8"):
        problems.append("keywords.txt: a space after a comma wastes a byte")
    return problems


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "fastlane/metadata/en-US"
    problems = check(root)
    for p in problems:
        print(f"FAIL {p}")
    if not problems:
        print(f"OK store copy in {root}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
