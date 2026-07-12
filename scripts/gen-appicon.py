#!/usr/bin/env python3
"""Render La Berceuse's app icon — a low warm crescent moon over a deep
indigo-to-black night sky with a few soft stars — as a COMPLETE opaque
iPhone/iPad icon set.

Single-size icons can render blank on physical devices, and iOS app icons must
be OPAQUE (no alpha). We draw at high resolution with PIL and downsample.

Run:  python3 scripts/gen-appicon.py
"""
import os
import math
import json
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SET = os.path.join(HERE, "..", "Resources", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(SET, exist_ok=True)

# Night palette — deep indigo top fading to true-black bottom.
TOP    = (24, 22, 54)       # deep indigo
MID    = (14, 13, 34)
BOTTOM = (4, 4, 10)         # near-black
MOON   = (247, 214, 150)    # warm amber moon
MOON_GLOW = (245, 176, 90)  # amber halo
STAR   = (226, 224, 238)    # faint cool star


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(px):
    S = 1024
    img = Image.new("RGB", (S, S), BOTTOM)
    d = ImageDraw.Draw(img)

    # Vertical gradient sky: indigo -> mid -> black.
    for y in range(S):
        t = y / (S - 1)
        if t < 0.5:
            col = lerp(TOP, MID, t / 0.5)
        else:
            col = lerp(MID, BOTTOM, (t - 0.5) / 0.5)
        d.line([(0, y), (S, y)], fill=col)

    # Soft stars (a quiet scatter, brighter near the top).
    stars = [
        (180, 200, 5), (300, 140, 3), (760, 180, 6), (860, 300, 4),
        (640, 110, 3), (130, 360, 4), (900, 460, 3), (250, 520, 3),
        (520, 240, 4), (430, 150, 2), (700, 420, 3),
    ]
    star_layer = Image.new("RGB", (S, S), (0, 0, 0))
    sd = ImageDraw.Draw(star_layer)
    for (sx, sy, r) in stars:
        for rr, fade in ((r * 3, 0.25), (r * 2, 0.5), (r, 1.0)):
            col = tuple(int(c * fade) for c in STAR)
            sd.ellipse([sx - rr, sy - rr, sx + rr, sy + rr], fill=col)
    star_layer = star_layer.filter(ImageFilter.GaussianBlur(1.2))
    img = _add_layers(img, star_layer)
    d = ImageDraw.Draw(img)

    # Warm halo behind the moon.
    cx, cy, R = int(S * 0.60), int(S * 0.42), int(S * 0.20)
    halo = Image.new("RGB", (S, S), (0, 0, 0))
    hd = ImageDraw.Draw(halo)
    for i in range(6, 0, -1):
        rr = int(R * (1 + i * 0.16))
        fade = 0.10 * (1 - i / 7)
        col = tuple(int(c * fade) for c in MOON_GLOW)
        hd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=col)
    halo = halo.filter(ImageFilter.GaussianBlur(22))
    img = _add_layers(img, halo)
    d = ImageDraw.Draw(img)

    # Crescent moon: a full warm disc minus an offset shadow disc.
    moon = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(moon)
    md.ellipse([cx - R, cy - R, cx + R, cy + R], fill=255)
    shadow = Image.new("L", (S, S), 0)
    shd = ImageDraw.Draw(shadow)
    off = int(R * 0.42)
    shd.ellipse([cx - R + off, cy - R - int(R * 0.10),
                 cx + R + off, cy + R - int(R * 0.10)], fill=255)
    # Crescent = moon AND NOT shadow.
    import PIL.ImageChops as IC
    crescent = IC.subtract(moon, shadow)
    crescent = crescent.filter(ImageFilter.GaussianBlur(1.4))
    moon_rgb = Image.new("RGB", (S, S), MOON)
    img.paste(moon_rgb, (0, 0), crescent)

    if px != S:
        img = img.resize((px, px), Image.LANCZOS)
    return img.convert("RGB")  # ensure opaque, no alpha


def _add_layers(base, layer):
    """Additive blend without numpy (pixel-safe screen-ish add)."""
    import PIL.ImageChops as IC
    return IC.add(base, layer)


# Render uses additive blends for stars/halo; do it with ImageChops always for
# determinism (the numpy branch above is bypassed by routing through _add_layers).
def render_safe(px):
    return render(px)


# NOTE: no iPad @1x slots — they only applied to iPads targeting iOS < 10 and
# putting @2x-sized PNGs in them triggers asset-catalog warnings on every build
# (our deployment target is iOS 17).
sizes = [40, 58, 60, 80, 87, 120, 167, 152, 180, 1024]
for s in sizes:
    render_safe(s).save(os.path.join(SET, f"icon-{s}.png"))

contents = {
    "images": [
        {"idiom": "iphone", "scale": "2x", "size": "20x20", "filename": "icon-40.png"},
        {"idiom": "iphone", "scale": "3x", "size": "20x20", "filename": "icon-60.png"},
        {"idiom": "iphone", "scale": "2x", "size": "29x29", "filename": "icon-58.png"},
        {"idiom": "iphone", "scale": "3x", "size": "29x29", "filename": "icon-87.png"},
        {"idiom": "iphone", "scale": "2x", "size": "40x40", "filename": "icon-80.png"},
        {"idiom": "iphone", "scale": "3x", "size": "40x40", "filename": "icon-120.png"},
        {"idiom": "iphone", "scale": "2x", "size": "60x60", "filename": "icon-120.png"},
        {"idiom": "iphone", "scale": "3x", "size": "60x60", "filename": "icon-180.png"},
        {"idiom": "ipad", "scale": "2x", "size": "20x20", "filename": "icon-40.png"},
        {"idiom": "ipad", "scale": "2x", "size": "29x29", "filename": "icon-58.png"},
        {"idiom": "ipad", "scale": "2x", "size": "40x40", "filename": "icon-80.png"},
        {"idiom": "ipad", "scale": "2x", "size": "76x76", "filename": "icon-152.png"},
        {"idiom": "ipad", "scale": "2x", "size": "83.5x83.5", "filename": "icon-167.png"},
        {"idiom": "ios-marketing", "scale": "1x", "size": "1024x1024", "filename": "icon-1024.png"},
    ],
    "info": {"author": "xcode", "version": 1},
}

with open(os.path.join(SET, "Contents.json"), "w") as f:
    f.write(json.dumps(contents, indent=2) + "\n")

print(f"OK — {len(sizes)} opaque icon PNGs written to {SET}")
