#!/usr/bin/env python3
"""
Polish App Store screenshot scaffolds with ambient glow effects
and copy to final/ directory at exact App Store dimensions.
"""

from PIL import Image, ImageDraw, ImageFilter
import os

CANVAS_W = 1290
CANVAS_H = 2796

# Amber glow color matching the app's accent
GLOW_COLOR = (255, 187, 0)

SCREENSHOTS = [
    ("01-talk-without-signal", (255, 170, 0)),    # warm amber
    ("02-relay-through-mesh", (50, 130, 255)),     # blue
    ("03-translate-any-language", (255, 187, 0)),  # amber
    ("04-text-off-grid", (100, 140, 255)),         # indigo
    ("05-encrypt-everything", (48, 209, 88)),      # green
]

BASE = "/root/Chirp/screenshots"


def add_glow(img, color, center_x, center_y, radius=400, intensity=0.15):
    """Add a soft radial glow behind the device."""
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)

    # Draw concentric circles with decreasing opacity
    for r in range(radius, 0, -4):
        alpha = int(255 * intensity * (r / radius) ** 0.5)
        alpha = min(alpha, 60)
        draw.ellipse(
            [center_x - r, center_y - r, center_x + r, center_y + r],
            fill=(*color, alpha)
        )

    glow = glow.filter(ImageFilter.GaussianBlur(radius=80))
    return Image.alpha_composite(img.convert("RGBA"), glow)


def add_top_accent_line(img, color):
    """Add a thin accent line below the headline area."""
    draw = ImageDraw.Draw(img)
    line_y = 680
    margin = 200
    draw.line(
        [(margin, line_y), (CANVAS_W - margin, line_y)],
        fill=(*color, 40),
        width=2
    )
    return img


def polish(name, accent_color):
    scaffold_path = os.path.join(BASE, name, "scaffold.png")
    if not os.path.exists(scaffold_path):
        print(f"  Skip {name} — no scaffold")
        return

    img = Image.open(scaffold_path).convert("RGBA")

    # Add ambient glow centered on the device/screen area
    device_center_x = CANVAS_W // 2
    device_center_y = 1400  # roughly middle of the device frame
    img = add_glow(img, accent_color, device_center_x, device_center_y, radius=500, intensity=0.12)

    # Add subtle top glow for the headline area
    img = add_glow(img, accent_color, CANVAS_W // 2, 300, radius=350, intensity=0.06)

    # Save polished version
    final_dir = os.path.join(BASE, "final")
    os.makedirs(final_dir, exist_ok=True)
    output = os.path.join(final_dir, f"{name}.png")
    img.convert("RGB").save(output, "PNG")
    print(f"  {output} ({CANVAS_W}x{CANVAS_H})")


def main():
    print("Polishing screenshots...")
    for name, color in SCREENSHOTS:
        polish(name, color)
    print("Done.")


if __name__ == "__main__":
    main()
