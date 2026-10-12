#!/usr/bin/env python3
# Builds docs/character-sheet.pdf: every character Senatorial should have, on one US Letter sheet, in light, regular
# and double struck. Characters the typewriter already has are cut straight from the scans in glyphs/ at true size;
# accented letters show their bare letter, to draw the accent over; anything else is left blank, to draw in.
# Each one is labelled underneath in grey.
#
#   python3 docs/character-sheet.py [path/to/Inconsolata.ttf]
#
# Needs Pillow, and Node with Playwright to print the PDF.

import base64, html, io, os, subprocess, sys, unicodedata
from PIL import Image

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The same measurements index.coffee uses to find a glyph in the scans
atlasDPI = 1200
charactersPerInch = 11
atlasLayout = "!\"#$%_&'()*+ 1234567890-= QWERTYUIOP¼ qwertyuiop½ ASDFGHJKL:@ asdfghjkl;¢ ZXCVBNM,.? zxcvbnm,./".split()
sx, sy = 75, 110
gw, gh = atlasDPI / charactersPerInch, atlasDPI / 8
pad = gw * 0.4
skew = 1.3
baseline = 128 # where the letters sit, measured down from the top of a glyph's cell in the scans

def atlasPos(c):
    for y, row in enumerate(atlasLayout):
        x = row.find(c)
        if x != -1:
            return sx + 2 * x * gw, sy + 2 * y * gh - x * skew
    return None

# Every character, roughly in the order you'd look for it. The arrows are a first guess, to be settled.
sheet = [
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "abcdefghijklmnopqrstuvwxyz",
    "0123456789",
    "`~!@#$%^&*()-_=+[]{}\\|;:'\",.<>/?",
    "¼½¢£€¥©®™°±×÷≠≈≤≥∞√∫∑∏∂∆Ωµπƒ◊¬¹²³¾",
    "‘’“”‚„‹›«»–—…·•¡¿§¶†‡‰ªº⁄¦¤",
    "´¨ˆ˜¸˛˝ˇ¯˘˙˚",
    "ÆæŒœØøÅåÇçßıÐðÞþ",
    "ÀÁÂÄÃàáâäãÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÖÕòóôöõÙÚÛÜùúûüÑñÝýŸÿ",
    "←→↑↓↖↗↘↙↰↱↲↳↵⤴⤵↺↻",
    "‸✓✗★",
]
chars = list(dict.fromkeys("".join(sheet)))

# Letters the scans have without their accent (or slash, or ring), shown bare to draw the rest on
bare = {"Ø": "O", "ø": "o"}
def base(c):
    if c in bare: return bare[c]
    b = unicodedata.normalize("NFD", c)[0]
    return b if b != c and b.isalpha() else None

def crop(img, c):
    gx, gy = atlasPos(c)
    box = tuple(round(v) for v in (gx - pad, gy - pad, gx + gw + pad, gy + gh + pad))
    buf = io.BytesIO()
    img.crop(box).convert("L").save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()

weights = [("Light", "light"), ("Regular", "regular"), ("Double struck", "double")]
inch = lambda px: f"{px / atlasDPI:.4f}in"

sections = []
for title, name in weights:
    img = Image.open(os.path.join(root, "glyphs", name + ".png"))
    cells = []
    for c in chars:
        shown = c if atlasPos(c) else base(c)
        glyph = f'<img src="{crop(img, shown)}">' if shown and atlasPos(shown) else ""
        label = html.escape(c)
        cells.append(f'<div class="cell"><div class="glyph">{glyph}</div><div class="label">{label}</div></div>')
    sections.append(f'<section><h2>{title}</h2><div class="grid">{"".join(cells)}</div></section>')

font = sys.argv[1] if len(sys.argv) > 1 else None
fontSrc = f"url('file://{os.path.abspath(font)}')" if font else \
    "url('https://fonts.gstatic.com/s/inconsolata/v37/QldgNThLqRwH-OJ1UHjlKENVzkWGVkL3GZQmAwLYxYWI2qfdm7Lpp4U8aRo.ttf')"

page = f"""<!doctype html><meta charset="utf-8"><title>Senatorial Character Sheet</title>
<style>
@font-face {{ font-family: Inconsolata; src: {fontSrc}; }}
@page {{ size: 8.5in 11in; margin: 0 }}
* {{ box-sizing: border-box }}
body {{ margin: 0; font-family: Inconsolata, 'DejaVu Sans Mono', monospace; color: #000 }}
main {{ width: 8.5in; height: 11in; padding: 0.5in 0.55in }}
h1 {{ font-size: 10pt; font-weight: 600; margin: 0 0 0.02in; letter-spacing: 0.04em }}
p {{ font-size: 7pt; color: #888; margin: 0 0 0.06in }}
h2 {{ font-size: 8pt; font-weight: 600; margin: 0.1in 0 0.02in; letter-spacing: 0.04em }}
.grid {{ display: grid; grid-template-columns: repeat(30, 0.2466in) }}
.cell {{ height: 0.335in; display: flex; flex-direction: column; align-items: center }}
.glyph {{ position: relative; width: {inch(gw)}; height: 0.22in; border-bottom: 0.5pt dotted #ddd }}
.glyph img {{ position: absolute; left: {inch(-pad)}; bottom: {inch(baseline - gh - pad)}; width: {inch(gw + 2 * pad)};
  height: {inch(gh + 2 * pad)}; mix-blend-mode: multiply }}
.label {{ font-size: 6pt; line-height: 0.09in; color: #999; margin-top: 0.03in }}
</style>
<main>
<h1>SENATORIAL CHARACTER SHEET</h1>
<p>Glyphs are at true size, cut from the scans. Draw what's missing above its label; accented letters show the bare letter, to draw the accent over.</p>
{"".join(sections)}
</main>"""

out = os.path.join(root, "docs", "character-sheet")
open(out + ".html", "w").write(page)
printer = """
const { chromium } = require(require('child_process').execSync('npm root -g').toString().trim() + '/playwright');
(async () => {
  const b = await chromium.launch(), p = await b.newPage();
  await p.goto('file://' + process.argv[1]); await p.evaluate(() => document.fonts.ready);
  await p.pdf({ path: process.argv[2], preferCSSPageSize: true, printBackground: true });
  await b.close();
})();"""
subprocess.run(["node", "-e", printer, out + ".html", out + ".pdf"], check=True)
os.remove(out + ".html")
print(f"{len(chars)} characters → {out}.pdf")
