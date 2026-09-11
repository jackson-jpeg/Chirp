#!/usr/bin/env python3
"""
App Store screenshot set composer for ChirpChirps.

Extends compose.py's device-frame technique with the brand treatment the
raw captures deserve: the app's slate-900 dark world, amber accent pulled
from the app icon, a tuning-dial motif across the set (each shot is one
"channel" on the dial), condensed poster type. One short headline per
shot, supplied by the manifest below.

Inputs:  screenshots/raw/<nn>-<name>.png   (real simulator captures)
Outputs: fastlane/screenshots/en-US/<nn>-<name>-69.png  (1290x2796, 6.9")
         fastlane/screenshots/en-US/<nn>-<name>-65.png  (1242x2688, 6.5")

Fonts: fonts/ (Barlow Condensed + IBM Plex Mono, OFL, licenses alongside).
"""

import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.abspath(__file__))

# ── Canvas (6.9 inch master; 6.5 inch is derived) ────────────────────
CANVAS_W = 1290
CANVAS_H = 2796
DERIVED_65 = (1242, 2688)

# ── Device frame (must match generate_frame.py / assets) ────────────
DEVICE_W = 1030
BEZEL = 15
SCREEN_W = DEVICE_W - 2 * BEZEL  # 1000
SCREEN_CORNER_R = 62
DEVICE_Y = 760
FRAME_PATH = os.path.join(ROOT, "assets", "device_frame.png")

# ── Palette: the app's own world ─────────────────────────────────────
BG_TOP = (15, 23, 42)        # slate900, the app background
BG_BOTTOM = (8, 12, 24)      # deeper floor of the same blue-black
CREAM = (242, 236, 220)      # warm headline white, vintage paper
AMBER = (255, 184, 0)        # Constants.Colors.amber, from the icon
TICK = (60, 74, 104)         # slate tick marks
TICK_DIM = (42, 53, 78)

# ── Type ─────────────────────────────────────────────────────────────
HEADLINE_FONT = os.path.join(ROOT, "fonts", "BarlowCondensed-Bold.ttf")
MONO_FONT = os.path.join(ROOT, "fonts", "IBMPlexMono-Medium.ttf")
HEADLINE_MAX = 168
HEADLINE_MIN = 92
HEADLINE_W = 1130
LINE_GAP = 14
MARGIN = 96

SHOTS = [
    ("01-talk", "TALK", "Walkie-talkie. No signal needed."),
    ("02-mesh", "MESH", "Phones nearby form the network."),
    ("03-messages", "TEXT", "Text when you can't talk."),
    ("04-voice", "VOICE", "Leave a message for when they're back."),
    ("05-map", "MAP", "See who's around."),
    ("06-privacy", "SECURE", "Encrypted between channel members. Nothing leaves your phone."),
]


def vertical_gradient(size, top, bottom):
    w, h = size
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        grad.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return grad.resize((w, h))


def tracked_text(draw, center_x, y, text, font, fill, tracking):
    """Center text with letterspacing (PIL has no native tracking)."""
    widths = [draw.textlength(ch, font=font) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x = center_x - total / 2
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=font, fill=fill)
        x += w + tracking
    return total


def wrap_lines(draw, text, font, max_w):
    words, lines, cur = text.split(), [], ""
    for w in words:
        test = f"{cur} {w}".strip()
        if draw.textlength(test, font=font) <= max_w:
            cur = test
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def fit_headline(draw, text, max_w, max_h):
    """Largest size where the wrapped headline fits the text band."""
    for size in range(HEADLINE_MAX, HEADLINE_MIN - 1, -4):
        font = ImageFont.truetype(HEADLINE_FONT, size)
        lines = wrap_lines(draw, text, font, max_w)
        ascent, descent = font.getmetrics()
        line_h = ascent + descent
        block_h = len(lines) * line_h + (len(lines) - 1) * LINE_GAP
        if block_h <= max_h and all(draw.textlength(l, font=font) <= max_w for l in lines):
            return font, lines, line_h, block_h
    font = ImageFont.truetype(HEADLINE_FONT, HEADLINE_MIN)
    lines = wrap_lines(draw, text, font, max_w)
    ascent, descent = font.getmetrics()
    line_h = ascent + descent
    return font, lines, line_h, len(lines) * line_h + (len(lines) - 1) * LINE_GAP


def draw_dial(draw, index, count, y):
    """Tuning-dial strip: tick marks with the amber needle on this shot's
    channel. The one piece of ornament, and it encodes the set's order."""
    left, right = MARGIN, CANVAS_W - MARGIN
    step = 24
    n_ticks = (right - left) // step + 1
    for i in range(n_ticks):
        x = left + i * step
        major = i % 5 == 0
        h = 30 if major else 16
        color = TICK if major else TICK_DIM
        draw.line([x, y + (34 - h), x, y + 34], fill=color, width=3)

    needle_x = left + (right - left) * (index + 0.5) / count
    draw.line([needle_x, y - 14, needle_x, y + 40], fill=AMBER, width=5)
    draw.polygon(
        [(needle_x - 9, y - 26), (needle_x + 9, y - 26), (needle_x, y - 12)],
        fill=AMBER,
    )


def compose_shot(index, name, band, headline, raw_path, out_69, out_65):
    canvas = vertical_gradient((CANVAS_W, CANVAS_H), BG_TOP, BG_BOTTOM).convert("RGBA")

    # Soft amber glow rising from behind the device: warm tube-radio light.
    glow = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        [CANVAS_W // 2 - 620, DEVICE_Y - 160, CANVAS_W // 2 + 620, DEVICE_Y + 560],
        fill=(*AMBER, 22),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    canvas = Image.alpha_composite(canvas, glow)

    draw = ImageDraw.Draw(canvas)

    # 1. Dial strip + channel readout
    draw_dial(draw, index, len(SHOTS), y=150)
    mono = ImageFont.truetype(MONO_FONT, 42)
    tracked_text(draw, CANVAS_W // 2, 236, f"CH 0{index + 1} · {band}", mono, AMBER, tracking=10)

    # 2. Headline, centered in the band between readout and device
    band_top, band_bottom = 340, DEVICE_Y - 60
    font, lines, line_h, block_h = fit_headline(
        draw, headline.upper(), HEADLINE_W, band_bottom - band_top
    )
    y = band_top + (band_bottom - band_top - block_h) // 2
    for line in lines:
        draw.text((CANVAS_W // 2, y), line, font=font, fill=CREAM, anchor="ma")
        y += line_h + LINE_GAP

    # 3. Real capture inside the rounded screen area (compose.py technique)
    device_x = (CANVAS_W - DEVICE_W) // 2
    screen_x, screen_y = device_x + BEZEL, DEVICE_Y + BEZEL

    shot = Image.open(raw_path).convert("RGBA")
    scale = SCREEN_W / shot.width
    shot = shot.resize((SCREEN_W, int(shot.height * scale)), Image.LANCZOS)

    screen_h = CANVAS_H - screen_y + 500
    scr_mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(scr_mask).rounded_rectangle(
        [screen_x, screen_y, screen_x + SCREEN_W, screen_y + screen_h],
        radius=SCREEN_CORNER_R, fill=255,
    )
    scr_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(scr_layer).rounded_rectangle(
        [screen_x, screen_y, screen_x + SCREEN_W, screen_y + screen_h],
        radius=SCREEN_CORNER_R, fill=(0, 0, 0, 255),
    )
    scr_layer.paste(shot, (screen_x, screen_y))
    scr_layer.putalpha(scr_mask)
    canvas = Image.alpha_composite(canvas, scr_layer)

    # 4. Device frame on top
    frame = Image.open(FRAME_PATH).convert("RGBA")
    frame_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    frame_layer.paste(frame, (device_x, DEVICE_Y))
    canvas = Image.alpha_composite(canvas, frame_layer)

    # 5. Save 6.9", derive 6.5" from the same composition
    final = canvas.convert("RGB")
    final.save(out_69, "PNG")
    print(f"  {out_69} ({CANVAS_W}x{CANVAS_H})")

    w65, h65 = DERIVED_65
    scale_h = int(round(CANVAS_H * (w65 / CANVAS_W)))  # 2691 for 1242
    resized = final.resize((w65, scale_h), Image.LANCZOS)
    resized.crop((0, 0, w65, h65)).save(out_65, "PNG")
    print(f"  {out_65} ({w65}x{h65})")


def main():
    raw_dir = os.path.join(ROOT, "screenshots", "raw")
    out_dir = os.path.join(ROOT, "fastlane", "screenshots", "en-US")
    os.makedirs(out_dir, exist_ok=True)

    for index, (name, band, headline) in enumerate(SHOTS):
        raw = os.path.join(raw_dir, f"{name}.png")
        if not os.path.exists(raw):
            raise SystemExit(f"missing raw capture: {raw}")
        compose_shot(
            index, name, band, headline, raw,
            os.path.join(out_dir, f"{name}-69.png"),
            os.path.join(out_dir, f"{name}-65.png"),
        )
    print("done")


if __name__ == "__main__":
    main()
