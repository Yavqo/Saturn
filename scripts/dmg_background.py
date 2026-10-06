#!/usr/bin/env python3
"""Draws the background of the Saturn installer window (white, Yavqo style). Usage: dmg_background.py out.png
Needs Pillow; make-dmg.sh simply skips the background if it isn't installed."""
import sys, os
from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]
S = 2                                   # draw at 2x so it is sharp on Retina screens
W, H = 660 * S, 400 * S
INK, MUTED, BLUE, SOFT = (28, 43, 51), (93, 108, 123), (0, 100, 224), (241, 244, 247)

def font(size, bold=False):
    for path, idx in [("/System/Library/Fonts/Helvetica.ttc", 1 if bold else 0), ("/System/Library/Fonts/SFNS.ttf", 0),
                      ("/Library/Fonts/Arial.ttf", 0)]:
        try:
            return ImageFont.truetype(path, size * S, index=idx)
        except Exception:
            continue
    return ImageFont.load_default()

img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)

def centered(text, y, f, fill):
    w = d.textlength(text, font=f)
    d.text(((W - w) / 2, y * S), text, font=f, fill=fill)

centered("Install Saturn", 34, font(28, True), INK)
centered("Drag Saturn into your Applications folder.", 76, font(15), MUTED)

# soft panel behind the two icons
d.rounded_rectangle([60 * S, 118 * S, 600 * S, 332 * S], radius=28 * S, fill=SOFT)

# arrow between the app icon (x=180) and the Applications shortcut (x=480)
y = 215 * S
x0, x1 = 262 * S, 398 * S
d.line([(x0, y), (x1 - 8 * S, y)], fill=BLUE, width=5 * S)
d.polygon([(x1, y), (x1 - 20 * S, y - 13 * S), (x1 - 20 * S, y + 13 * S)], fill=BLUE)

centered("First time opening it? Right-click Saturn and choose Open.", 352, font(12), MUTED)
img.save(out, dpi=(144, 144))
