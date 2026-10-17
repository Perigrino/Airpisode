#!/usr/bin/env python3
"""Round 2: refined variants of the Calendar (3) and Rail (8) concepts."""
import os, subprocess

OUT = "/Users/perigrino/Projects/Airpisode/Design/icon-concepts/round2"
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

# ---------- Calendar ----------

# 3a — classic: gradient body, white header band, white tabs, white play
icons["3a-calendar-classic"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<rect x="372" y="256" width="56" height="96" rx="28" fill="#fff"/>
<rect x="596" y="256" width="56" height="96" rx="28" fill="#fff"/>
<clipPath id="ca"><rect x="272" y="312" width="480" height="456" rx="60"/></clipPath>
<g clip-path="url(#ca)">
  <rect x="272" y="312" width="480" height="456" fill="url(#g)"/>
  <rect x="272" y="312" width="480" height="116" fill="#fff"/>
</g>
<path d="M421 500 L421 692 L603 596 Z" fill="#fff"/>''')

# 3b — month grid with the release day highlighted as a play
cells = []
for r in range(3):
    for c in range(4):
        x = 327 + c * 98
        y = 376 + r * 98
        if r == 1 and c == 2:
            cells.append(f'<rect x="{x}" y="{y}" width="76" height="76" rx="20" fill="url(#g)"/>')
            cells.append(f'<path d="M{x+20} {y+20} L{x+20} {y+56} L{x+56} {y+38} Z" fill="#fff"/>')
        else:
            cells.append(f'<rect x="{x}" y="{y}" width="76" height="76" rx="20" fill="#fff" opacity="0.12"/>')
icons["3b-calendar-grid"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<rect x="380" y="264" width="52" height="88" rx="26" fill="url(#g)"/>
<rect x="592" y="264" width="52" height="88" rx="26" fill="url(#g)"/>
<rect x="280" y="316" width="464" height="444" rx="56" fill="#15131F" stroke="url(#g)" stroke-width="5"/>
''' + "".join(cells))

# 3c — white body, gradient header, gradient play
icons["3c-calendar-inverse"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<rect x="372" y="256" width="56" height="96" rx="28" fill="url(#g)"/>
<rect x="596" y="256" width="56" height="96" rx="28" fill="url(#g)"/>
<clipPath id="cb"><rect x="272" y="312" width="480" height="456" rx="60"/></clipPath>
<g clip-path="url(#cb)">
  <rect x="272" y="312" width="480" height="456" fill="#fff"/>
  <rect x="272" y="312" width="480" height="116" fill="url(#g)"/>
</g>
<path d="M421 500 L421 692 L603 596 Z" fill="url(#g)"/>''')

# ---------- Rail ----------

# 8a — the rail's top node IS the play (integrated, one mark)
icons["8a-rail-node"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<rect x="482" y="356" width="60" height="396" rx="30" fill="url(#g)" opacity="0.9"/>
<circle cx="512" cy="356" r="106" fill="#fff"/>
<path d="M470 304 L470 408 L562 356 Z" fill="url(#g)"/>
<circle cx="512" cy="540" r="40" fill="none" stroke="#fff" stroke-width="20"/>
<circle cx="512" cy="676" r="32" fill="none" stroke="#fff" stroke-width="16"/>''')

# 8b — rail with a play badge (alert dot becomes a play)
icons["8b-rail-badge"] = svg(DARK + GRAD, squircle("url(#dark)") + '''
<rect x="430" y="300" width="64" height="440" rx="32" fill="url(#g)" opacity="0.85"/>
<circle cx="462" cy="372" r="40" fill="#fff"/>
<circle cx="462" cy="512" r="34" fill="none" stroke="#fff" stroke-width="18"/>
<circle cx="462" cy="652" r="28" fill="none" stroke="#fff" stroke-width="16"/>
<circle cx="666" cy="330" r="112" fill="#0A0A0E"/>
<circle cx="666" cy="330" r="88" fill="url(#g)"/>
<path d="M638 288 L638 372 L710 330 Z" fill="#fff"/>''')

# 8c — gradient tile: white rail, gradient play node, dark dots
icons["8c-rail-light"] = svg(GRAD, squircle("url(#g)") + '''
<rect x="474" y="336" width="76" height="404" rx="38" fill="#fff"/>
<circle cx="512" cy="336" r="98" fill="url(#g)"/>
<path d="M478 290 L478 382 L562 336 Z" fill="#fff"/>
<circle cx="512" cy="530" r="34" fill="#0A0A0E"/>
<circle cx="512" cy="656" r="27" fill="#0A0A0E"/>''')

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
for i, name in enumerate(names):
    r, c = divmod(i, cols)
    x = pad + c*(cell+pad); y = pad + r*(cell+label_h+pad)
    ic = Image.open(os.path.join(OUT, name + ".png")).convert("RGBA").resize((cell, cell), Image.LANCZOS)
    sheet.paste(ic, (x, y), ic)
    draw.text((x+2, y+cell+10), name.replace("-", " "), fill=(235,235,245), font=f_name)
sheet_path = os.path.join(OUT, "compare.png")
sheet.save(sheet_path)
print("compare:", sheet_path, sheet.size)
