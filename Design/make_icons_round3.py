#!/usr/bin/env python3
"""Round 3: redesign Calendar (3) and Rail (8) against Logoinspo principles.

Principles applied (logoinspo.com):
  1. High contrast  - bold value changes, no thin hairlines, no busy textures.
  2. Abstract       - geometric cues, not literal illustrations.
  3. Restrained     - one tile + white + one gradient. Nothing else.
  4. Bold geometry  - sturdy, structural marks with generous safe margins.
  5. Legible @16px  - every element survives downscaling (checked in the sheet).
  6. Vibrant purple->pink gradient (2026 trend).
"""
import os, subprocess

OUT = "/Users/perigrino/Projects/Airpisode/Design/icon-concepts/round3"
os.makedirs(OUT, exist_ok=True)
W = 1024

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


def squircle(fill):
    return f'<rect x="100" y="100" width="824" height="824" rx="190" fill="{fill}"/>'


def svg(defs, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{W}" '
            f'viewBox="0 0 {W} {W}"><defs>{defs}</defs>{body}</svg>')


# Bold play triangle, centered at (cx, cy), width w, height h.
def play(cx, cy, w, h, fill):
    hw, hh = w / 2, h / 2
    return f'<path d="M{cx-hw:.0f} {cy-hh:.0f} L{cx-hw:.0f} {cy+hh:.0f} L{cx+hw:.0f} {cy:.0f} Z" fill="{fill}"/>'


icons = {}

# ---------------- Calendar ----------------

# 3a - page + band: gradient tile, one white page, one gradient header band, one gradient play.
icons["3a-page-band"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<clipPath id="p3a"><rect x="240" y="268" width="544" height="528" rx="84"/></clipPath>
<g clip-path="url(#p3a)">
  <rect x="240" y="268" width="544" height="528" fill="#fff"/>
  <rect x="240" y="268" width="544" height="150" fill="url(#g)"/>
</g>
''' + play(512, 607, 192, 212, "url(#g)"))

# 3b - bold tabs: dark tile, one white page, two bold gradient tabs, one gradient play.
icons["3b-tabs"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<rect x="336" y="176" width="88" height="140" rx="44" fill="url(#g)"/>
<rect x="600" y="176" width="88" height="140" rx="44" fill="url(#g)"/>
<rect x="240" y="232" width="544" height="564" rx="84" fill="#fff"/>
''' + play(512, 560, 192, 212, "url(#g)"))

# 3c - knockout: gradient tile, white page, gradient band, play is negative space.
icons["3c-knockout"] = svg(DARK + GRAD, squircle("url(#g)") + '''
<mask id="hole">
  <rect x="0" y="0" width="1024" height="1024" fill="#fff"/>
  <path d="M416 501 L416 713 L608 607 Z" fill="#000"/>
</mask>
<g mask="url(#hole)">
  <clipPath id="p3c"><rect x="240" y="268" width="544" height="528" rx="84"/></clipPath>
  <g clip-path="url(#p3c)">
    <rect x="240" y="268" width="544" height="528" fill="#fff"/>
    <rect x="240" y="268" width="544" height="150" fill="#7B3FE4"/>
  </g>
</g>''')

# ---------------- Rail ----------------

# 8a - node + ring: dark tile, one thick rail, play node on top, one bold ring node.
icons["8a-node-ring"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<rect x="472" y="380" width="80" height="380" rx="40" fill="url(#g)" opacity="0.95"/>
<circle cx="512" cy="380" r="128" fill="#fff"/>
''' + play(512, 380, 112, 120, "url(#g)") + '''
<circle cx="512" cy="612" r="58" fill="none" stroke="#fff" stroke-width="30"/>''')

# 8b - fade: dark tile, play node, rail that fades out below it. Purest "countdown".
icons["8b-fade"] = svg(DARK + GRAD + FADE, squircle("url(#dark)") + '''
<rect x="480" y="356" width="64" height="420" rx="32" fill="url(#fade)"/>
<circle cx="512" cy="356" r="130" fill="#fff"/>
''' + play(512, 356, 116, 124, "url(#g)"))

# 8c - light: gradient tile, thick white rail, gradient play node, one dark dot.
icons["8c-light"] = svg(GRAD, squircle("url(#g)") + '''
<rect x="466" y="360" width="92" height="400" rx="46" fill="#fff"/>
<circle cx="512" cy="360" r="120" fill="url(#g)"/>
''' + play(512, 360, 108, 116, "#fff") + '''
<circle cx="512" cy="640" r="46" fill="#0A0A0E"/>''')

names = list(icons.keys())
for name, s in icons.items():
    sp = os.path.join(OUT, name + ".svg")
    pp = os.path.join(OUT, name + ".png")
    open(sp, "w").write(s)
    subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", sp, "-o", pp], check=True)
    print("rendered", pp)

from PIL import Image, ImageDraw, ImageFont
cols, rows = 3, 2
cell, pad, label_h = 340, 26, 46
sheet = Image.new("RGB", (cols*cell + pad*(cols+1), rows*(cell+label_h) + pad*(rows+1)), (12, 12, 16))
draw = ImageDraw.Draw(sheet)

def font(size):
    for p in ["/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf"]:
        try: return ImageFont.truetype(p, size)
        except Exception: pass
    return ImageFont.load_default()

f_name = font(22)
f_small = font(13)
for i, name in enumerate(names):
    r, c = divmod(i, cols)
    x = pad + c*(cell+pad); y = pad + r*(cell+label_h+pad)
    big = Image.open(os.path.join(OUT, name + ".png")).convert("RGBA")
    ic = big.resize((cell, cell), Image.LANCZOS)
    sheet.paste(ic, (x, y), ic)
    # legibility check: 64px and 32px renders beside the label
    t64 = big.resize((64, 64), Image.LANCZOS)
    t32 = big.resize((32, 32), Image.LANCZOS)
    sheet.paste(t64, (x + cell - 104, y + cell + 4), t64)
    sheet.paste(t32, (x + cell - 34, y + cell + 22), t32)
    draw.text((x + 2, y + cell + 12), name.replace("-", " "), fill=(235, 235, 245), font=f_name)
    draw.text((x + cell - 104, y + cell + 30), "64 / 32", fill=(150, 150, 165), font=f_small)
sheet_path = os.path.join(OUT, "compare.png")
sheet.save(sheet_path)
print("compare:", sheet_path, sheet.size)
