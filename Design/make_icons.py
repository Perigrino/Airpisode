#!/usr/bin/env python3
"""Render 10 app-icon concepts for Airpisode to PNG + a labeled contact sheet."""
import os, subprocess, sys

OUT = "/Users/perigrino/Projects/Airpisode/Design/icon-concepts"
os.makedirs(OUT, exist_ok=True)
W = 1024

GRAD = ('<linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#9A6BF5"/>'
        '<stop offset="1" stop-color="#D959D9"/></linearGradient>')
DARK = ('<radialGradient id="dark" cx="0.35" cy="0.18" r="1.05">'
        '<stop offset="0" stop-color="#1C1538"/>'
        '<stop offset="1" stop-color="#0A0A0E"/></radialGradient>')

def squircle(fill):
    return f'<rect x="100" y="100" width="824" height="824" rx="190" fill="{fill}"/>'

def svg(defs, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{W}" '
            f'viewBox="0 0 {W} {W}"><defs>{defs}</defs>{body}</svg>')

icons = {}

# 1 — Play TV
icons["01-play-tv"] = svg(GRAD, squircle("url(#g)") + '''
<rect x="292" y="336" width="440" height="352" rx="46" fill="none" stroke="#fff" stroke-width="36"/>
<path d="M462 418 L462 606 L636 512 Z" fill="#fff"/>''')

# 2 — Countdown ring
icons["02-countdown-ring"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<circle cx="512" cy="512" r="252" fill="none" stroke="url(#g)" stroke-width="60"
  stroke-linecap="round" stroke-dasharray="1267 1584" transform="rotate(-90 512 512)"/>
<path d="M421 416 L421 608 L603 512 Z" fill="url(#g)"/>''')

# 3 — Calendar + play
icons["03-calendar-play"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<rect x="380" y="280" width="52" height="88" rx="26" fill="#fff"/>
<rect x="592" y="280" width="52" height="88" rx="26" fill="#fff"/>
<rect x="288" y="324" width="448" height="424" rx="56" fill="url(#g)"/>
<path d="M421 440 L421 632 L603 536 Z" fill="#fff"/>''')

# 4 — Bell + play (play knocked out)
icons["04-bell-play"] = svg(GRAD, squircle("url(#g)") + '''
<mask id="bellmask">
  <path d="M512 296 C 404 296 352 372 352 468 C 352 556 322 606 300 636 L 724 636 C 702 606 672 556 672 468 C 672 372 620 296 512 296 Z" fill="#fff"/>
  <rect x="278" y="632" width="468" height="52" rx="26" fill="#fff"/>
  <circle cx="512" cy="716" r="30" fill="#fff"/>
  <path d="M478 424 L478 592 L624 512 Z" fill="#000"/>
</mask>
<rect x="100" y="100" width="824" height="824" rx="190" fill="#fff" mask="url(#bellmask)"/>''')

# 5 — Film strip + play
icons["05-film-play"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<rect x="352" y="264" width="320" height="496" rx="34" fill="url(#g)"/>
<rect x="368" y="308" width="42" height="42" rx="12" fill="#0A0A0E"/>
<rect x="368" y="430" width="42" height="42" rx="12" fill="#0A0A0E"/>
<rect x="368" y="552" width="42" height="42" rx="12" fill="#0A0A0E"/>
<rect x="614" y="308" width="42" height="42" rx="12" fill="#0A0A0E"/>
<rect x="614" y="430" width="42" height="42" rx="12" fill="#0A0A0E"/>
<rect x="614" y="552" width="42" height="42" rx="12" fill="#0A0A0E"/>
<path d="M456 424 L456 600 L614 512 Z" fill="#fff"/>''')

# 6 — Play disc
icons["06-play-disc"] = svg(GRAD, squircle("url(#g)") + '''
<circle cx="512" cy="512" r="262" fill="#fff"/>
<path d="M456 408 L456 616 L648 512 Z" fill="url(#g)"/>''')

# 7 — Stacked cards
icons["07-stacked-cards"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<rect x="260" y="336" width="424" height="424" rx="56" fill="url(#g)" opacity="0.35"/>
<rect x="300" y="376" width="424" height="424" rx="56" fill="url(#g)" opacity="0.65"/>
<rect x="340" y="416" width="424" height="424" rx="56" fill="url(#g)"/>
<path d="M482 544 L482 712 L620 628 Z" fill="#fff"/>''')

# 8 — Countdown rail + play
icons["08-rail-play"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<rect x="372" y="264" width="60" height="496" rx="30" fill="url(#g)"/>
<circle cx="402" cy="336" r="40" fill="#fff"/>
<circle cx="402" cy="512" r="34" fill="none" stroke="#fff" stroke-width="18"/>
<circle cx="402" cy="688" r="28" fill="none" stroke="#fff" stroke-width="16"/>
<path d="M566 424 L566 600 L700 512 Z" fill="#fff"/>''')

# 9 — Spark + play
icons["09-spark-play"] = svg(GRAD, squircle("url(#g)") + '''
<path d="M512 212 C 540 400 624 484 812 512 C 624 540 540 624 512 812 C 484 624 400 540 212 512 C 400 484 484 400 512 212 Z" fill="#fff"/>
<path d="M478 436 L478 588 L614 512 Z" fill="url(#g)"/>''')

# 10 — Play + notification badge
icons["10-play-badge"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<circle cx="500" cy="540" r="200" fill="#fff"/>
<path d="M446 452 L446 628 L614 540 Z" fill="url(#g)"/>
<circle cx="712" cy="330" r="112" fill="#0A0A0E"/>
<circle cx="712" cy="330" r="88" fill="url(#g)"/>''')

names = list(icons.keys())
for name, s in icons.items():
    svg_path = os.path.join(OUT, name + ".svg")
    png_path = os.path.join(OUT, name + ".png")
    with open(svg_path, "w") as f:
        f.write(s)
    subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", svg_path, "-o", png_path], check=True)
    print("rendered", png_path)

# ---- Contact sheet ----
from PIL import Image, ImageDraw, ImageFont

cols, rows = 5, 2
cell, pad, label_h = 330, 26, 46
sheet_w = cols * cell + pad * (cols + 1)
sheet_h = rows * (cell + label_h) + pad * (rows + 1)
sheet = Image.new("RGB", (sheet_w, sheet_h), (12, 12, 16))
draw = ImageDraw.Draw(sheet)

def font(size):
    for p in ["/System/Library/Fonts/SFNS.ttf",
              "/System/Library/Fonts/Supplemental/Arial.ttf",
              "/System/Library/Fonts/Helvetica.ttc"]:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    return ImageFont.load_default()

f_num = font(30)
f_name = font(20)

for i, name in enumerate(names):
    r, c = divmod(i, cols)
    x = pad + c * (cell + pad)
    y = pad + r * (cell + label_h + pad)
    icon = Image.open(os.path.join(OUT, name + ".png")).convert("RGBA").resize((cell, cell), Image.LANCZOS)
    sheet.paste(icon, (x, y), icon)
    label = f"{i+1}. {name.split('-', 1)[1].replace('-', ' ')}"
    draw.text((x + 2, y + cell + 10), label, fill=(235, 235, 245), font=f_name)

sheet_path = os.path.join(OUT, "contact-sheet.png")
sheet.save(sheet_path)
print("contact sheet:", sheet_path, sheet.size)
