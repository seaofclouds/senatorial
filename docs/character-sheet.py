#!/usr/bin/env python3
# Builds docs/character-sheet.pdf: every character Senatorial should have, on one US Letter sheet, in light, regular
# and double struck, and docs/character-sheet-red.pdf, the same in the red half of the ribbon. Characters the
# typewriter already has are cut straight from the scans in glyphs/ at true size; anything else is left blank, to draw
# in. Accents are drawn once each, for capitals and for lowercase, beside a typed letter to line them up against, and
# laid over typed letters later. Each character is labelled underneath in grey, and framed by a tick either side,
# alternately non-photo blue and green, at its baseline (or, for an accent, where the accent sits).
#
#   python3 docs/character-sheet.py [path/to/Inconsolata.ttf]
#
# Needs Pillow, and Node with Playwright to print the PDF.

import base64, html, io, os, subprocess, sys
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

# Every character, roughly in the order you'd look for it. Accented letters aren't here: see accents below.
sheet = [
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "abcdefghijklmnopqrstuvwxyz",
    "0123456789",
    "`~!@#$%^&*()-_=+[]{}\\|;:'\",.<>/?",
    "¼½¢£€¥©®™°±×÷≠≈≤≥∞√∫∑∏∂∆Ωµπƒ◊¬¹²³¾",
    "‘’“”‚„‹›«»–—…·•¡¿§¶†‡‰ªº⁄¦¤",
    "˛˝ˇ¯˘˙",
    "ÆæŒœßıÐðÞþ",
    "←→↑↓↖↗↘↙↰↱↲↳↶↷⤵↺↻",
    "‸✓✗★",
]
chars = list(dict.fromkeys("".join(sheet)))

# Each accent is drawn once over a capital and once over a lowercase letter, in the blanks following a typed letter to
# line them up against, and laid over any letter that takes it (accented i's over the dotless ı). The ticks in a blank
# sit where the accent does: just above the capitals or the lowercase, or on the baseline for the ones that hang below
# or cross the letter.
capAccent, lowAccent = 143, 115 # pixels above the baseline in the scans, a little over the capitals and the x-height
accents = [ # (typed letter, the accented letters to draw beside it, how far above the baseline their accents sit)
    ("A", "ÀÁÂÄÃÅ", capAccent), ("C", "Ç", 0), ("O", "Ø", 0),
    ("a", "àáâäãå", lowAccent), ("c", "ç", 0), ("o", "ø", 0),
]

def crop(img, c):
    gx, gy = atlasPos(c)
    box = tuple(round(v) for v in (gx - pad, gy - pad, gx + gw + pad, gy + gh + pad))
    buf = io.BytesIO()
    img.crop(box).convert("RGB").save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()

# Characters that come out tiny in any font, so their labels are set larger
smallLabels = set("¹²³¼½¾ªº˛˝ˇ¯˘˙·‚„‘’“”™")

inch = lambda px: f"{px / atlasDPI:.4f}in"
columns = 32

def cell(label, glyph="", lift=0):
    small = " small" if label in smallLabels else ""
    return (f'<div class="cell" style="--lift: {inch(lift)}"><div class="glyph">{glyph}</div>'
            f'<div class="label{small}">{html.escape(label)}</div></div>')

def section(title, atlas):
    img = Image.open(os.path.join(root, "glyphs", atlas + ".png"))
    typed = lambda c: f'<img src="{crop(img, c)}">' if atlasPos(c) else ""
    cells = [cell(c, typed(c)) for c in chars]
    # The accents start a row of their own, so each letter stays with its blanks
    cells += ['<div class="cell gap"></div>'] * (-len(cells) % columns)
    for letter, accented, lift in accents:
        cells += [cell(letter, typed(letter))] + [cell(c, lift=lift) for c in accented]
    return f'<section><h2>{title}</h2><div class="grid">{"".join(cells)}</div></section>'

font = sys.argv[1] if len(sys.argv) > 1 else None
fontSrc = f"url('file://{os.path.abspath(font)}')" if font else \
    "url('https://fonts.gstatic.com/s/inconsolata/v37/QldgNThLqRwH-OJ1UHjlKENVzkWGVkL3GZQmAwLYxYWI2qfdm7Lpp4U8aRo.ttf')"

style = f"""
@font-face {{ font-family: Inconsolata; src: {fontSrc}; }}
@page {{ size: 8.5in 11in; margin: 0 }}
* {{ box-sizing: border-box }}
body {{ margin: 0; font-family: Inconsolata, 'DejaVu Sans Mono', monospace; color: #000 }}
main {{ width: 8.5in; height: 11in; padding: 0.35in 0.4in }}
h1 {{ font-size: 10pt; font-weight: 600; margin: 0; letter-spacing: 0.04em }}
h2 {{ font-size: 8pt; font-weight: 600; margin: 0.06in 0 0; letter-spacing: 0.04em }}
.grid {{ display: grid; grid-template-columns: repeat({columns}, 0.24in) }}
.cell {{ position: relative; height: 0.455in; display: flex; flex-direction: column; align-items: center }}
/* Room above the capitals for accents; the bottom edge is the baseline */
.glyph {{ position: relative; width: {inch(gw)}; height: 0.26in; flex: none }}
.glyph img {{ position: absolute; left: {inch(-pad)}; bottom: {inch(baseline - gh - pad)}; width: {inch(gw + 2 * pad)};
  height: {inch(gh + 2 * pad)}; mix-blend-mode: multiply }}
/* A short tick either side frames each character at its baseline (or where its accent sits), alternately non-photo
   blue and green so it's clear where one ends and the next begins, leaving the space to draw in clear */
.cell:not(.gap) .glyph::before, .cell:not(.gap) .glyph::after {{ content: ""; position: absolute; bottom: var(--lift);
  width: 0.018in; border-bottom: 0.4pt solid #a4dded }}
.cell:nth-child(even) .glyph::before, .cell:nth-child(even) .glyph::after {{ border-color: #92d38b }}
.glyph::before {{ left: -0.058in }} .glyph::after {{ right: -0.058in }}
/* Clear space under the baseline for descenders, then the label, then room above the next row's accents */
.label {{ font-size: 8.5pt; line-height: 0.11in; color: #666; margin-top: 0.075in }}
.label.small {{ font-size: 11.5pt }}
"""

printer = """
const { chromium } = require(require('child_process').execSync('npm root -g').toString().trim() + '/playwright');
(async () => {
  const b = await chromium.launch(), p = await b.newPage();
  await p.goto('file://' + process.argv[1]); await p.evaluate(() => document.fonts.ready);
  await p.pdf({ path: process.argv[2], preferCSSPageSize: true, printBackground: true });
  await b.close();
})();"""

# The red half of the ribbon was only scanned light and regular; the app strikes double struck red as regular
sheets = [
    ("character-sheet", "Character Sheet", [("Light", "light"), ("Regular", "regular"), ("Double struck", "double")]),
    ("character-sheet-red", "Character Sheet Red", [("Light", "light-red"), ("Regular", "regular-red")]),
]
for file, title, weights in sheets:
    out = os.path.join(root, "docs", file)
    page = f"""<!doctype html><meta charset="utf-8"><title>{title}</title><style>{style}</style>
<main><h1>{title.upper()}</h1>{"".join(section(name, atlas) for name, atlas in weights)}</main>"""
    open(out + ".html", "w").write(page)
    subprocess.run(["node", "-e", printer, out + ".html", out + ".pdf"], check=True)
    os.remove(out + ".html")
    print(f"{len(chars)} characters and {sum(len(a) for _, a, _ in accents)} accents × {len(weights)} → {out}.pdf")
