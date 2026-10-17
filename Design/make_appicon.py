#!/usr/bin/env python3
"""Render the chosen "8b fade" mark into a full macOS AppIcon set.

The mark: a play node with a rail that dissolves downward - a countdown to release.
Restrained to one tile + white + one gradient (Logoinspo rules).
"""
import json, os, subprocess

ROOT = "/Users/perigrino/Projects/Airpisode"
OUT = os.path.join(ROOT, "Airpisode/Resources/Assets.xcassets/AppIcon.appiconset")
os.makedirs(OUT, exist_ok=True)

GRAD = ('<linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#9A6BF5"/>'
        '<stop offset="1" stop-color="#D959D9"/></linearGradient>')
DARK = ('<radialGradient id="dark" cx="0.35" cy="0.18" r="1.05">'
        '<stop offset="0" stop-color="#1C1538"/>'
        '<stop offset="1" stop-color="#0A0A0E"/></radialGradient>')
FADE = ('<linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#B073F0" stop-opacity="0.95"/>'
        '<stop offset="0.65" stop-color="#C96BE0" stop-opacity="0.35"/>'
        '<stop offset="1" stop-color="#D959D9" stop-opacity="0"/></linearGradient>')

SVG = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>{GRAD}{DARK}{FADE}</defs>
<rect x="100" y="100" width="824" height="824" rx="190" fill="url(#dark)"/>
<rect x="478" y="364" width="68" height="412" rx="34" fill="url(#fade)"/>
<circle cx="512" cy="364" r="138" fill="#fff"/>
<path d="M452 300 L452 428 L572 364 Z" fill="url(#g)"/>
</svg>'''

svg_path = os.path.join(ROOT, "Design/appicon-8b.svg")
open(svg_path, "w").write(SVG)

# macOS AppIcon slots: (filename, pixel size)
slots = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
for name, size in slots:
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), svg_path,
                    "-o", os.path.join(OUT, name)], check=True)
    print("rendered", name, size)

images = []
for name, size in slots:
    scale = 2 if "@2x" in name else 1
    base = size // scale
    images.append({"filename": name, "idiom": "mac",
                   "scale": f"{scale}x", "size": f"{base}x{base}"})
contents = {"images": images, "info": {"author": "xcode", "version": 1}}
open(os.path.join(OUT, "Contents.json"), "w").write(json.dumps(contents, indent=2) + "\n")
print("wrote Contents.json with", len(images), "entries")
