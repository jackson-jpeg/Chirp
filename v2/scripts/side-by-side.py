#!/usr/bin/env python3
"""Put each design PNG beside its simulator screenshot (light and dark) in one image.

    python3 v2/scripts/side-by-side.py <shots dir> <out dir>

Reads <Name>-light-build.png / <Name>-dark-build.png from the shots dir and
v2/design/<Name>.png, scales all three to the design's height, and writes
<Name>-compare.png (design | light | dark) to the out dir.
"""
import sys
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent.parent
shots, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
H = 1266  # half the design's 3x height keeps the files small

for design in sorted((HERE / "design").glob("*.png")):
    name = design.stem
    parts = [design] + [shots / f"{name}-{m}-build.png" for m in ("light", "dark")]
    if not all(p.exists() for p in parts[1:]):
        continue
    imgs = []
    for p in parts:
        im = Image.open(p).convert("RGB")
        imgs.append(im.resize((round(im.width * H / im.height), H), Image.LANCZOS))
    gap = 24
    canvas = Image.new("RGB", (sum(i.width for i in imgs) + gap * (len(imgs) - 1), H), "white")
    x = 0
    for im in imgs:
        canvas.paste(im, (x, 0))
        x += im.width + gap
    canvas.save(out / f"{name}-compare.png", optimize=True)
    print(out / f"{name}-compare.png")
