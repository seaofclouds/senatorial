#!/usr/bin/env python3
# Builds the glyph images in glyphs/ from the typewriter's own scans (scans/typed/) and the filled-in character sheets
# (scans/character-sheet-black.png and scans/character-sheet-red.png).
#
#   python3 docs/build-glyphs.py
#
# Each scanned sheet is lined up against the layout docs/character-sheet.py printed it from, by finding every typed
# glyph on it. Then each drawn glyph is cut out of its blank, cleaned of the blue and green ticks, and set at the
# height its kind of character sits at, centred in its cell. Accents are laid over the letters that take them.
# Needs Pillow and NumPy.

import json, os, sys
import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
here = lambda *p: os.path.join(root, *p)

# The typewriter's own scans, one for each strike, and where each glyph sits in them
atlasDPI = 1200
charactersPerInch = 11
atlasLayout = "!\"#$%_&'()*+ 1234567890-= QWERTYUIOP¼ qwertyuiop½ ASDFGHJKL:@ asdfghjkl;¢ ZXCVBNM,.? zxcvbnm,./".split()
sx, sy = 75, 110
gw, gh = atlasDPI / charactersPerInch, atlasDPI / 8
pad = gw * 0.4
skew = 1.3
baseline = 128 # where the letters sit, down from the top of a glyph's cell

def atlasPos(c):
    for y, row in enumerate(atlasLayout):
        x = row.find(c)
        if x != -1:
            return sx + 2 * x * gw, sy + 2 * y * gh - x * skew
    return None

typedScans = {}
def typedScan(name):
    if name not in typedScans: typedScans[name] = Image.open(here("scans", "typed", name + ".png")).convert("RGB")
    return typedScans[name]

def gray(img):
    return np.asarray(img.convert("L"), dtype=np.float32)

# LINING UP A SCAN ################################################################################

def ncc(window, template):
    """Normalised cross-correlation of template at every offset inside window."""
    th, tw = template.shape
    t = template - template.mean()
    tn = np.sqrt((t * t).sum()) or 1
    H, W = window.shape
    fh, fw = H + th, W + tw
    corr = np.fft.irfft2(np.fft.rfft2(window, (fh, fw)) * np.conj(np.fft.rfft2(t, (fh, fw))), (fh, fw))
    corr = corr[:H - th + 1, :W - tw + 1]
    # local sums of the window under the template, for its mean and spread
    ii = np.pad(window.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    ii2 = np.pad((window * window).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    box = lambda a: a[th:, tw:] - a[:-th, tw:] - a[th:, :-tw] + a[:-th, :-tw]
    s, s2 = box(ii), box(ii2)
    var = np.maximum(s2 - s * s / (th * tw), 1e-6)
    return corr / (np.sqrt(var) * tn)

def register(scan, sections, scale=4, radius=0.12):
    """Fit the affine map from sheet inches to scan pixels, by finding each typed glyph near where it was printed."""
    small = scan.resize((scan.width // scale, scan.height // scale), Image.LANCZOS)
    s = gray(small)
    dpi = atlasDPI / scale
    r = int(radius * dpi)
    src, dst, scores = [], [], []
    for sec in sections:
        atlas = typedScan(sec["atlas"])
        for c in sec["cells"]:
            if not c["typed"]: continue
            gx, gy = atlasPos(c["char"])
            crop = atlas.crop((round(gx - pad), round(gy - pad), round(gx + gw + pad), round(gy + gh + pad)))
            t = gray(crop.resize((crop.width // scale, crop.height // scale), Image.LANCZOS))
            # where the crop's top left corner was printed, in inches
            ex = c["x"] - pad / atlasDPI
            ey = c["y"] + c["h"] - (baseline + pad) / atlasDPI
            x0, y0 = round(ex * dpi) - r, round(ey * dpi) - r
            win = s[y0:y0 + t.shape[0] + 2 * r, x0:x0 + t.shape[1] + 2 * r]
            score = ncc(win, t)
            iy, ix = np.unravel_index(np.argmax(score), score.shape)
            src.append((ex * dpi, ey * dpi))
            dst.append((x0 + ix, y0 + iy))
            scores.append(score[iy, ix])
    src, dst, scores = np.array(src), np.array(dst, dtype=float), np.array(scores)
    keep = scores > 0.5
    for _ in range(4):
        M, *_ = np.linalg.lstsq(np.c_[src[keep], np.ones(keep.sum())], dst[keep], rcond=None)
        resid = np.linalg.norm(np.c_[src, np.ones(len(src))] @ M - dst, axis=1)
        keep = (scores > 0.5) & (resid < max(1.0, 3 * np.median(resid[keep])))
    # inches → scan pixels at full resolution
    M = M * scale
    M[:2] *= dpi
    return M, {"glyphs": len(src), "used": int(keep.sum()), "rms px": round(float(np.sqrt((resid[keep] ** 2).mean()) * scale), 2)}

# CUTTING OUT A DRAWN GLYPH #######################################################################

cellWidth = 0.24 # inches from one character's centre to the next on the sheets
below = 0.07     # how far under the baseline a blank reaches before its label begins

above = 0.26     # how far over the baseline a blank reaches, up to the label of the row above

def cutOut(scan, M, c):
    """The blank in cell c, straightened, at 1200 dpi, with the sheet's baseline at y = above * 1200."""
    x0 = c["x"] + c["w"] / 2 - cellWidth / 2
    y0 = c["y"] + c["h"] - above
    w, h = round(cellWidth * atlasDPI), round((above + below) * atlasDPI)
    a, d = M[0] / atlasDPI
    b, e = M[1] / atlasDPI
    cx, fy = np.array([x0, y0, 1]) @ M
    return scan.transform((w, h), Image.AFFINE, (a, b, cx, d, e, fy), resample=Image.BICUBIC, fillcolor=(255, 255, 255))

def components(mask):
    """Label 8-connected regions of a boolean mask: returns a list of (ys, xs) index arrays."""
    seen = np.zeros_like(mask, dtype=bool)
    H, W = mask.shape
    found = []
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]: continue
        stack, ys, xs = [(y, x)], [], []
        seen[y, x] = True
        while stack:
            cy, cx = stack.pop()
            ys.append(cy); xs.append(cx)
            for ny in (cy - 1, cy, cy + 1):
                for nx in (cx - 1, cx, cx + 1):
                    if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        found.append((np.array(ys), np.array(xs)))
    return found

def ink(img):
    """How much ink is at each pixel (0 for paper), ignoring the blue and green ticks printed on the sheet."""
    rgb = np.asarray(img, dtype=np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    amount = 255 - rgb.min(2)
    amount[(g - r > 18) | (b - r > 18)] = 0
    return amount

def drawn(img, red=False, threshold=70, smallest=40):
    """The pen marks in a cut-out blank, cleaned onto white paper, and their bounding box; None if it was left empty."""
    amount = ink(img)
    rgb = np.asarray(img, dtype=np.float32)
    redness = rgb[..., 0] - (rgb[..., 1] + rgb[..., 2]) / 2
    mask = amount > threshold
    H, W = mask.shape
    keep = np.zeros_like(mask)
    for ys, xs in components(mask):
        # Drop specks of dust, pencil, and strokes that wandered in from a neighbouring cell. Pen is darker than
        # pencil or dust, and on the red sheet it's red.
        if len(ys) < smallest or abs(xs.mean() - W / 2) > W * 0.42: continue
        dark = amount[ys, xs].mean()
        if (redness[ys, xs].mean() < 50) if red else (dark < 120): continue
        if len(ys) < 60 and dark < 140: continue
        keep[ys, xs] = True
    if not keep.any(): return None
    # take in the soft edges around the strokes kept
    grown = keep.copy()
    for _ in range(3):
        grown[1:] |= grown[:-1]; grown[:-1] |= grown[1:]; grown[:, 1:] |= grown[:, :-1]; grown[:, :-1] |= grown[:, 1:]
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    grown &= ~((g - r > 18) | (b - r > 18))
    clean = np.where(grown[..., None], rgb, 255).astype(np.uint8)
    ys, xs = np.nonzero(keep)
    return clean, (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)

# WHERE EACH KIND OF CHARACTER SITS ###############################################################

# Measured off the typed glyphs, in pixels at 1200 dpi down from the top of a glyph's cell in the typewriter's scans
line = {"base": 126, "cap": -5, "x": 23, "axis": 74, "paren": 62, "comma": 85}
centre = 58 # across: the typed glyphs sit a little right of their cells' middle
gap = 12    # between a letter and the accent over it

# How each drawn character is set: the edge (or middle) of its ink that goes on which line. Anything not listed sits
# on the baseline.
placing = {}
for chars, rule in [
    ("¹²³ª º°™‘’“”`^˝ˇ¯˘˙", ("top", "cap")),       # raised
    ("þƒ", ("top", "cap")),                        # tall, and hanging below the baseline
    ("µ¡¿", ("top", "x")),                         # x-height, and hanging below
    ("‚„", ("top", "comma")),                      # low quotes, where a comma sits
    ("˛", ("top", "base")),                        # under the baseline
    ("×÷±≠≈–—~·•¬<>«»‹›∞←→≤≥¤", ("middle", "axis")),
    ("[]{}|\\¦∫⁄", ("middle", "paren")),
]:
    for c in chars.replace(" ", ""): placing[c] = rule

# The accented letters, built from an accent drawn once for capitals and once for lowercase. Accented i's take theirs
# over the dotless ı.
accentOf = {"À": "grave", "Á": "acute", "Â": "circumflex", "Ä": "diaeresis", "Ã": "tilde", "Å": "ring", "Ç": "cedilla",
            "Ø": "slash"}
accented = {
    "grave": "ÀÈÌÒÙàèìòù", "acute": "ÁÉÍÓÚÝáéíóúý", "circumflex": "ÂÊÎÔÛâêîôû", "diaeresis": "ÄËÏÖÜŸäëïöüÿ",
    "tilde": "ÃÑÕãñõ", "ring": "Åå", "cedilla": "Çç", "slash": "Øø",
}
spacingAccents = {"´": "acute", "¨": "diaeresis", "ˆ": "circumflex", "˜": "tilde", "¸": "cedilla", "˚": "ring"}
import unicodedata
def baseOf(c):
    b = {"Ø": "O", "ø": "o"}.get(c) or unicodedata.normalize("NFD", c)[0]
    return "ı" if b == "i" else b

# THE NEW GLYPH IMAGES ############################################################################

# Every strike gets one image: the typed glyphs copied from the typewriter's scans, then the drawn ones. Built at
# 1200 dpi and saved at 600, the resolution pages are printed and exported at.
outDPI = 600
columns = 24
cellW, cellH = 200, 360          # at 1200 dpi, a glyph's cell plus room around it for accents and descenders
padX, padY = gw * 0.4, gh * 2 / 3 # how much around its cell the app takes with each glyph
originX, originY = round((cellW - gw) / 2), round((cellH - gh) / 2)

strikes = [ # (glyph image, sheet, section on it, typed scan)
    ("light", "black", 0, "light"), ("regular", "black", 1, "regular"), ("double", "black", 2, "double"),
    ("light-red", "red", 0, "light-red"), ("regular-red", "red", 1, "regular-red"),
    ("double-red", "red", 2, "regular-red"), # the typewriter's red was never scanned double struck
]

def inkBox(rgb, threshold=90):
    ys, xs = np.nonzero(255 - rgb.min(2).astype(np.float32) > threshold)
    return None if len(ys) == 0 else (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)

def stamp(canvas, rgb, x, y):
    """Lay rgb over canvas with its top left at (x, y), ink over ink, as a typist's strikes would."""
    h, w = rgb.shape[:2]
    region = canvas[y:y + h, x:x + w]
    region[...] = np.minimum(region, rgb[:region.shape[0], :region.shape[1]])

def setDrawn(canvas, ox, oy, d, rule=None, at=None):
    """Set a drawn glyph d = (clean, box) in the cell whose glyph origin is (ox, oy), by rule or at a given point."""
    clean, (x0, y0, x1, y1) = d
    m = 4
    piece = clean[max(y0 - m, 0):y1 + m, max(x0 - m, 0):x1 + m]
    w, h = x1 - x0, y1 - y0
    if at is not None: # (centre x, edge, value) for accents
        cx, edge, v = at
    else:
        edge, which = rule or ("bottom", "base")
        cx, v = centre, line[which]
    left = cx - w / 2
    top = {"top": v, "bottom": v - h, "middle": v - h / 2}[edge]
    stamp(canvas, piece, round(ox + left) - (x0 - max(x0 - m, 0)), round(oy + top) - (y0 - max(y0 - m, 0)))

def build():
    # Every drawing on both sheets, by sheet and section
    drawings = {}
    for sheet, scanFile in [("black", "character-sheet-black"), ("red", "character-sheet-red")]:
        layout = json.load(open(here("docs", "character-sheet" + ("-red" if sheet == "red" else "") + "-layout.json")))
        scan = Image.open(here("scans", scanFile + ".png")).convert("RGB")
        M, fit = register(scan, layout)
        print(f"{sheet} sheet lined up from {fit['used']} of {fit['glyphs']} typed glyphs, to within {fit['rms px']} px")
        for i, sec in enumerate(layout):
            got = drawings[sheet, i] = {}
            for c in sec["cells"]:
                if c["typed"]: continue
                d = drawn(cutOut(scan, M, c), red=sheet == "red")
                if d is not None: got[c["char"]] = (d[0], (d[1][0], d[1][1], d[1][2], d[1][3]))
    # A character left blank in one section borrows its drawing from another of the same colour
    for (sheet, i), got in drawings.items():
        for (other, j), there in drawings.items():
            if other != sheet: continue
            for c, d in there.items(): got.setdefault(c, d)
    typed = "".join(dict.fromkeys("".join(atlasLayout)))
    accentCells = set(accentOf) | {c.lower() for c in accentOf}
    drawnChars = [c for c in drawings["black", 1] if c not in accentCells and c not in typed]
    composed = [c for k in accented for c in accented[k]]
    order = list(typed) + drawnChars + composed + list(spacingAccents)
    rows = -(-len(order) // columns)

    for name, sheet, i, typedName in strikes:
        canvas = np.full((rows * cellH, columns * cellW, 3), 255, np.uint8)
        got = drawings[sheet, i]
        scanned = np.asarray(typedScan(typedName))
        def origin(c):
            n = order.index(c)
            return (n % columns) * cellW + originX, (n // columns) * cellH + originY
        def drawCell(c, ox, oy):
            if c in typed:
                gx, gy = atlasPos(c)
                x, y = round(gx - pad), round(gy - pad)
                stamp(canvas, scanned[y:y + round(gh + 2 * pad), x:x + round(gw + 2 * pad)], ox - round(pad), oy - round(pad))
            elif c in got:
                setDrawn(canvas, ox, oy, got[c], placing.get(c))
        for c in typed + "".join(drawnChars):
            drawCell(c, *origin(c))
        # The accents, as drawn after a capital and after a lowercase letter
        accents = {}
        for c, kind in accentOf.items():
            for case, ch in (("cap", c), ("low", c.lower())):
                if ch in got: accents[kind, case] = got[ch]
        for kind, letters in accented.items():
            for c in letters:
                ox, oy = origin(c)
                drawCell(baseOf(c), ox, oy)
                case = "cap" if c.isupper() else "low"
                if (kind, case) not in accents: continue
                x0, y0, x1, y1 = inkBox(canvas[oy - originY:oy - originY + cellH, ox - originX:ox - originX + cellW])
                bx, by0, by1 = (x0 + x1) / 2 - originX, y0 - originY, y1 - originY
                if kind == "slash": at = (bx, "middle", (by0 + by1) / 2)
                elif kind == "cedilla": at = (bx, "top", line["base"] - 6)
                else: at = (bx, "bottom", by0 - gap)
                setDrawn(canvas, ox, oy, accents[kind, case], at=at)
        for c, kind in spacingAccents.items():
            if (kind, "low") not in accents: continue
            ox, oy = origin(c)
            at = (centre, "top", line["base"] - 6) if kind == "cedilla" else (centre, "bottom", line["x"] - gap)
            setDrawn(canvas, ox, oy, accents[kind, "low"], at=at)
        img = Image.fromarray(canvas).resize((canvas.shape[1] * outDPI // atlasDPI, canvas.shape[0] * outDPI // atlasDPI), Image.LANCZOS)
        # Black ink is saved as greys; red as a palette of 256 colours, plenty for red ink on white paper
        img = img.quantize(256, dither=Image.Dither.NONE) if "red" in name else img.convert("L")
        img.save(here("glyphs", name + ".png"), optimize=True)
        print(f"glyphs/{name}.png: {img.width} × {img.height}")
    s = outDPI / atlasDPI
    json.dump({"dpi": outDPI, "columns": columns, "cellWidth": cellW * s, "cellHeight": cellH * s,
               "glyphX": originX * s, "glyphY": originY * s, "chars": "".join(order)},
              open(here("glyphs", "layout.json"), "w"), ensure_ascii=False)
    print(f"{len(order)} characters: {len(typed)} typed, {len(drawnChars)} drawn, {len(composed) + len(spacingAccents)} built from accents")

if __name__ == "__main__":
    build()
