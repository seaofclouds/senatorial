# TYPE SCALE ######################################################################################

# Everything is measured in real-world inches, so pages come out at their true physical size
charactersPerInch = 11 # this is based on the actual typewriter
linesPerInch = 6 # standard typewriter line feed — single spacing is 1/6"
atlasDPI = 1200 # ROUGHLY — this is based on the glyph scan Todd sent me
exportDPI = 600 # Resolution of saved & printed pages. Change it to whatever you want, and everything Just Works™

# PAPER ###########################################################################################

mm = (v)-> v / 25.4

# Sizes are in inches, portrait (or the way the sheet is usually fed, for cards)
papers =
  letter: short: "Letter", name: "US Letter — 8½ × 11", w: 8.5, h: 11
  legal: short: "Legal", name: "US Legal — 8½ × 14", w: 8.5, h: 14
  halfLetter: short: "Half Letter", name: "Half Letter — 5½ × 8½", w: 5.5, h: 8.5
  executive: short: "Executive", name: "Executive — 7¼ × 10½", w: 7.25, h: 10.5
  a4: short: "A4", name: "A4 — 210 × 297 mm", w: mm(210), h: mm(297)
  a5: short: "A5", name: "A5 — 148 × 210 mm", w: mm(148), h: mm(210)
  a6: short: "A6", name: "A6 — 105 × 148 mm", w: mm(105), h: mm(148)
  card3x5: short: "3×5 Card", name: "Index Card — 5 × 3", w: 5, h: 3
  card4x6: short: "4×6 Card", name: "Index Card — 6 × 4", w: 6, h: 4
  card5x8: short: "5×8 Card", name: "Index Card — 8 × 5", w: 8, h: 5
  custom: short: "Custom", name: "Custom…"

defaults =
  paper: "letter"
  customW: 8.5
  customH: 11
  landscape: false
  spacing: 1
  left: 11 # left margin stop, in columns from the left edge of the paper (11 = 1")
  right: 11 # right margin, in columns in from the right edge of the paper
  top: 6 # top margin, in lines from the top edge of the paper (6 = 1")
  bottom: 6 # bottom margin, in lines up from the bottom edge of the paper
  tabs: [] # tab stops, in columns from the left edge of the paper. When empty, there's a stop every 5 columns.
  atlas: "regular"
  red: false
  center: false # how the very first line is aligned, before anything's been typed

defaultTabInterval = 5

clamp = (v, lo, hi)-> Math.max lo, Math.min hi, v

# Work out the character grid for the current sheet
geometry = ()->
  if settings.paper is "custom"
    [w, h] = [settings.customW, settings.customH]
  else
    {w, h} = papers[settings.paper] ? papers.letter
  [w, h] = [h, w] if settings.landscape
  cols = Math.floor w * charactersPerInch
  rows = Math.floor h * linesPerInch
  left = clamp settings.left, 0, cols - 1
  right = clamp cols - settings.right, left + 1, cols # the column where each line ends
  top = clamp settings.top, 0, rows - 1
  bottom = clamp settings.bottom, 0, rows - top - 1
  spacing = settings.spacing
  linesPerPage = Math.max 1, Math.floor((rows - top - bottom - 1) / spacing) + 1
  {w, h, cols, rows, left, right, top, bottom, spacing, linesPerPage}

# Where the given line of a page sits, in inches from the top of the sheet
lineTop = (g, line)-> (g.top + line * g.spacing) / linesPerInch

# Find the next tab stop to the right of col, or null if there isn't one before the right margin
nextTab = (g, col)->
  stops = if settings.tabs.length then settings.tabs else defaultTabs g
  ahead = (stop for stop in stops when col < stop < g.right)
  if ahead.length then Math.min ahead... else null

defaultTabs = (g)-> (c for c in [g.left + defaultTabInterval...g.right] by defaultTabInterval)

# ATLAS ###########################################################################################

# We assume that the provided glyph images will be an atlas of characters arranged in this pattern
# We also assume that the characters in this atlas have a single space between them
atlasLayout = "!\"#$%_&'()*+ 1234567890-= QWERTYUIOP¼ qwertyuiop½ ASDFGHJKL:@ asdfghjkl;¢ ZXCVBNM,.? zxcvbnm,./".split /\s/

# Top left corner in atlas — just eyeball it
sx = 75
sy = 110

# Size of glyphs in the atlas
gw = atlasDPI / charactersPerInch
gh = atlasDPI / 8

# Shift the glyph down within its line so it sits nicely under the caret
verticalAlign = gh * .15

# How much extra space around the glyph should we include when copying the glyph from the atlas to the canvas?
# When this is zero, glyphs sometimes get cut off. If it's too big, you'll see bits of neighbouring glyphs.
pad = gw * 0.4

# The atlases are slightly rotated, so this tries to compensate
skew = 1.3

# Typographer's punctuation that the typewriter doesn't have, mapped to the keys you'd actually strike
substitutions = "‘": "'", "’": "'", "“": "\"", "”": "\"", "–": "-", "—": "-", "×": "x"

# This function returns the x,y pixel position within the atlas for a given character, or null if the character isn't in the atlas.
# The characters in the atlas have a single space between them, and the lines are double-spaced, so we multiply positions by 2 in both directions.
getGlyphPosInAtlas = (c)->
  for row, y in atlasLayout
    x = row.indexOf c
    if x isnt -1
      px = sx + (2 * x * gw)
      py = sy + (2 * y * gh) - x * skew # Compensate for the atlases being slightly tilted
      return [px, py]
  [null, null]

glyphCache = {}
glyph = (c)->
  glyphCache[c] ?= do ()->
    [gx, gy] = getGlyphPosInAtlas substitutions[c] ? c
    [gx, gy] = getGlyphPosInAtlas "*" unless gx? and gy?
    [gx, gy]

# Every character remembers how it was struck: regular, light, or double struck, on the black or red half of the ribbon,
# and whether its paragraph is centred. Styles are kept as a string with one base-36 digit per character, alongside the text.
weights = ["regular", "light", "double"]
styleCode = (weight, red, center = false)->
  (weights.indexOf(weight) * 2 + (if red then 1 else 0) + (if center then 6 else 0)).toString 36
styleValue = (code)-> parseInt code, 36
styleWeight = (code)-> weights[(styleValue(code) % 6) >> 1]
styleRed = (code)-> (styleValue(code) & 1) is 1
styleCenter = (code)-> styleValue(code) >= 6

# A paragraph runs up to & including its carriage return (or form feed)
breaks = ["\n", "\f"]
paragraphStart = (text, i)->
  i-- while i > 0 and text[i - 1] not in breaks
  i
paragraphEnd = (text, i)->
  i++ while i < text.length and text[i] not in breaks
  Math.min i + 1, text.length

# A paragraph's alignment is carried by its first character. An empty last line follows the line before it.
centeredAt = (text, codes, i)->
  s = paragraphStart text, i
  if s < text.length then styleCenter codes[s]
  else if s > 0 then styleCenter codes[s - 1]
  else settings.center

# These images store the glyph atlases, one per strike & ribbon colour
atlases = {}
atlasNames = ["regular", "light", "double", "regular-red", "light-red"]

atlasFor = (code)->
  name = styleWeight(code) + (if styleRed code then "-red" else "")
  name = "regular-red" if name is "double-red" # There's no red double struck scan
  atlases[name]

loadAtlases = ()->
  loaded = 0
  for name in atlasNames
    do (name)->
      img = new Image()
      img.onload = ()->
        atlases[name] = img
        invalidate()
        document.body.classList.add "ready" if ++loaded is atlasNames.length
      img.src = "glyphs/#{name}.png"

# LAYOUT ##########################################################################################

# Works out where every character lands: [page, line, col] for each index in the text,
# plus one extra entry for the end of the text (where the carriage sits after the last character).
# Words wrap at the right margin, tabs jump to the next stop, \n is a carriage return, and \f feeds a new sheet.
layout = null

doLayout = (g)->
  text = input.value
  n = text.length
  pos = new Array n + 1
  lines = [] # {page, line, start, end} — the range of indices whose caret position is on each line
  pages = [] # {start, end, firstLine}

  page = 0
  line = 0
  col = g.left

  newline = ()->
    col = g.left
    line++
    if line >= g.linesPerPage
      line = 0
      page++

  newpage = ()->
    col = g.left
    line = 0
    page++

  place = (i)->
    pos[i] = [page, line, col]
    last = lines[lines.length - 1]
    if last?.page is page and last.line is line
      last.end = i
    else
      if page isnt last?.page
        pages.push {start: i, firstLine: lines.length}
      lines.push {page, line, start: i, end: i, center: centeredAt text, styles, i}

  i = 0
  while i < n
    c = text[i]
    if c is "\n"
      place i++
      newline()
    else if c is "\f"
      place i++
      newpage()
    else if c is "\t"
      place i++
      stop = nextTab g, col
      if stop? then col = stop else newline()
    else if c is " "
      newline() if col > g.right # A space may hang just past the margin, but no further
      place i++
      col++
    else
      # Find the end of this word, and if it won't fit on this line, return the carriage first
      j = i
      j++ while j < n and text[j] not in [" ", "\n", "\t", "\f"]
      newline() if col + (j - i) > g.right and col > g.left
      while i < j
        newline() if col >= g.right # Words longer than a whole line get broken
        place i++
        col++
  place n

  # Centred lines are spaced in from the left margin by half the room left over, landing on the grid
  # the same way a typist would centre a line by backspacing from the middle
  blank = [" ", "\n", "\t", "\f"]
  for ln in lines when ln.center
    last = null
    last = i for i in [ln.start..ln.end] when i < n and text[i] not in blank
    width = if last? then pos[last][2] + 1 - g.left else 0
    shift = Math.max 0, Math.floor (g.right - g.left - width) / 2
    pos[i][2] += shift for i in [ln.start..ln.end]

  for p, k in pages
    p.end = pages[k + 1]?.start ? n + 1
    p.lastLine = (pages[k + 1]?.firstLine ? lines.length) - 1

  layout = {text, n, pos, lines, pages}

# Which entry in layout.lines holds index i?
lineIndexOf = (i)->
  lo = 0
  hi = layout.lines.length - 1
  while lo < hi
    mid = (lo + hi + 1) >> 1
    if layout.lines[mid].start <= i then lo = mid else hi = mid - 1
  lo

# The index on the given line whose caret position is closest to col
indexAtCol = (ln, col)->
  for i in [ln.start..ln.end]
    return i if layout.pos[i][2] >= col
  ln.end

# The index nearest to a spot on a page, in inches from the sheet's top left corner
indexAtPoint = (g, page, x, y)->
  return layout.n if page >= layout.pages.length
  return 0 if page < 0
  p = layout.pages[page]
  line = Math.floor (y * linesPerInch - g.top) / g.spacing
  ln = layout.lines[clamp p.firstLine + line, p.firstLine, p.lastLine]
  indexAtCol ln, Math.round x * charactersPerInch

# RENDERING #######################################################################################

$ = (q)-> document.querySelector q

pagesElm = $ ".pages"
selectionElm = $ ".selection"
caretElm = $ ".caret"
input = $ ".input"
deckElm = $ ".ui"
formatMenu = $ ".format"

pageViews = []
renderVersion = 0
geo = null
styles = "" # one style digit per character of the text — see styleCode

# Sheets are shown at actual size, so the type reads the way it would on the desk.
# A CSS inch isn't a real inch (it's about ⅗" on a phone), so this uses typical real screen densities instead.
actualSize = ()->
  if matchMedia("(pointer: coarse)").matches
    if Math.min(screen.width, screen.height) < 600 then 155 else 130 # phones, then tablets
  else
    120 # laptops & desktop monitors
pxPerInch = actualSize()

# Settings changed or the atlases loaded, so every page needs to be redrawn
invalidate = ()->
  renderVersion++
  render()

makePageView = ()->
  elm = document.createElement "div"
  elm.className = "page"
  canvas = document.createElement "canvas"
  guide = document.createElement "div"
  guide.className = "guide"
  label = document.createElement "button"
  label.className = "paper-label"
  label.title = "Change paper"
  label.onclick = openChooser
  strip = document.createElement "div"
  strip.className = "strip"
  top = document.createElement "div"
  top.className = "flag across vstop"
  top.dataset.kind = "top"
  bottom = document.createElement "div"
  bottom.className = "flag across vstop"
  bottom.dataset.kind = "bottom"
  spacing = makeLever "spacing", spacings, ((s)-> linesIcon 3 * s, "left"), ((s)-> changeSettings spacing: s)
  spacing.title = "Line spacing"
  elm.append canvas, guide, label, strip, top, bottom, spacing
  pagesElm.insertBefore elm, selectionElm
  {elm, canvas, guide, label, strip, top, bottom, spacing, ctx: canvas.getContext("2d"), key: null}

# Three little engraved lines, spaced apart by gap, flush left or centred
linesIcon = (gap, align)->
  widths = if align is "center" then [10, 6, 10] else [10, 10, 10]
  lines = for w, k in widths
    x1 = if align is "center" then 10 - w / 2 else 5
    y = 10 + (k - 1) * gap
    "<line x1='#{x1}' x2='#{x1 + w}' y1='#{y}' y2='#{y}'/>"
  "<svg viewBox='0 0 20 20'>#{lines.join ""}</svg>"

# A lever that clicks into one of a few positions, like the line space lever on an Olympia SM9
makeLever = (name, values, icon, choose)->
  lever = document.createElement "div"
  lever.className = "lever #{name}"
  lever.innerHTML = "<span class='knob'></span>"
  for value in values
    do (value)->
      btn = document.createElement "button"
      btn.dataset.value = value
      btn.innerHTML = icon value
      btn.addEventListener "pointerdown", (e)-> e.preventDefault() # Keep typing where you were
      btn.onclick = ()-> choose value
      lever.append btn
  lever

setLever = (lever, values, value)->
  k = Math.max 0, values.indexOf value
  lever.style.setProperty "--position", k
  btn.classList.toggle "active", i is k for btn, i in lever.querySelectorAll "button"
  null

render = ()->
  return unless settings?
  geo = g = geometry()
  doLayout g
  cssW = g.w * pxPerInch
  cssH = g.h * pxPerInch
  dpr = window.devicePixelRatio or 1

  pageViews.push makePageView() while pageViews.length < layout.pages.length
  pageViews.pop().elm.remove() while pageViews.length > layout.pages.length

  textBottom = lineTop(g, g.linesPerPage - 1) + 1 / linesPerInch

  for view, p in pageViews
    view.elm.style.width = cssW + "px"
    view.elm.style.height = cssH + "px"
    pw = Math.round cssW * dpr
    ph = Math.round cssH * dpr
    unless view.canvas.width is pw and view.canvas.height is ph
      view.canvas.width = pw
      view.canvas.height = ph
      view.key = null

    Object.assign view.guide.style,
      left: g.left / charactersPerInch * pxPerInch + "px"
      width: (g.right - g.left) / charactersPerInch * pxPerInch + "px"
      top: g.top / linesPerInch * pxPerInch + "px"
      height: (textBottom - g.top / linesPerInch) * pxPerInch + "px"

    view.label.textContent = paperName()
    view.top.style.top = g.top / linesPerInch * pxPerInch + "px"
    view.top.textContent = g.top
    view.top.title = "Top margin: #{g.top} lines (#{fmt g.top / linesPerInch} in)"
    view.bottom.style.top = (g.h - g.bottom / linesPerInch) * pxPerInch + "px"
    view.bottom.textContent = g.bottom
    view.bottom.title = "Bottom margin: #{g.bottom} lines (#{fmt g.bottom / linesPerInch} in) · #{g.linesPerPage} lines per page"
    view.spacing.style.top = g.top / linesPerInch * pxPerInch + 16 + "px"
    setLever view.spacing, spacings, settings.spacing
    renderStrip view, g

    # Only redraw pages whose contents actually changed
    {start, end} = layout.pages[p]
    key = "#{renderVersion}|#{pw}|#{layout.text.slice start, end}|#{styles.slice start, end}"
    unless view.key is key
      view.key = key
      drawPage view.ctx, p, pw / g.w

  slideCarriage carriageX
  renderSelection()

# Draw one page onto a canvas, at the given pixels per inch (screen, or exportDPI for saving)
drawPage = (ctx, p, ppi)->
  ctx.setTransform 1, 0, 0, 1, 0, 0
  ctx.globalCompositeOperation = "source-over"
  ctx.fillStyle = "#fff"
  ctx.fillRect 0, 0, ctx.canvas.width, ctx.canvas.height

  s = ppi / atlasDPI
  ctx.setTransform s, 0, 0, s, 0, 0
  ctx.imageSmoothingQuality = "high"

  # The extra padding on chars means they overlap, so this allows them to overlap nicely
  ctx.globalCompositeOperation = "darken"

  {start, end} = layout.pages[p]
  text = layout.text
  for i in [start...Math.min end, layout.n]
    c = text[i]
    continue if c in [" ", "\n", "\t", "\f"]
    img = atlasFor styles[i]
    continue unless img?
    [gx, gy] = glyph c
    [_, line, col] = layout.pos[i]
    px = col * gw
    py = lineTop(geo, line) * atlasDPI + verticalAlign
    ctx.drawImage img, gx - pad, gy - pad, gw + pad*2, gh + pad*2, px - pad, py - pad, gw + pad*2, gh + pad*2
  null

# Along the top of each sheet: the left & right margin tabs, the tab stops, and the centre mark
renderStrip = (view, g)->
  step = pxPerInch / charactersPerInch
  marks = [
    {kind: "center", col: g.w * charactersPerInch / 2, title: "Centre of the sheet"}
    {kind: "left", col: g.left, title: "Left margin at #{g.left} (#{fmt g.left / charactersPerInch} in)"}
    {kind: "right", col: g.right, title: "Right margin at #{g.right} (#{fmt (g.cols - g.right) / charactersPerInch} in from the edge) · #{g.right - g.left} characters per line"}
  ]
  for col, index in settings.tabs
    marks.push {kind: "tab", col, index, title: "Tab stop at #{col} — drag it away to clear it"}
  unless settings.tabs.length
    marks.push {kind: "default", col} for col in defaultTabs g

  elms = Array.from view.strip.querySelectorAll ".mark"
  while elms.length < marks.length
    elms.push e = document.createElement "div"
    view.strip.append e
  e.remove() for e in elms.splice marks.length
  for mark, k in marks
    e = elms[k]
    e.className = "mark " + switch mark.kind
      when "left", "right" then "flag down"
      when "tab" then "tabstop"
      when "center" then "center-mark"
      else "default-tab"
    e.classList.toggle "removing", drag?.kind is "tab" and drag.index is mark.index and drag.removing
    e.classList.toggle "dragging", drag?.kind is mark.kind and (mark.kind isnt "tab" or drag.index is mark.index)
    e.dataset.kind = mark.kind
    e.dataset.index = mark.index ? ""
    e.style.left = mark.col * step + "px"
    e.textContent = if mark.kind in ["left", "right"] then mark.col else ""
    e.title = mark.title ? ""
  null

# Caret position for index i, in CSS px relative to the .pages container
caretPoint = (i)->
  [page, line, col] = layout.pos[i]
  view = pageViews[page]
  x: view.elm.offsetLeft + col / charactersPerInch * pxPerInch
  y: view.elm.offsetTop + lineTop(geo, line) * pxPerInch
  h: pxPerInch / linesPerInch

focusIndex = ()->
  Math.min (if input.selectionDirection is "backward" then input.selectionStart else input.selectionEnd), layout.n

renderSelection = ()->
  return unless layout? and pageViews.length
  a = input.selectionStart
  b = input.selectionEnd

  # Caret goes on the moving end of the selection
  focus = focusIndex()
  c = caretPoint focus
  Object.assign caretElm.style, left: c.x - 1 + "px", top: c.y + "px", height: c.h + "px"
  Object.assign input.style, left: c.x + "px", top: c.y + "px", height: c.h + "px"

  # Restart the blink so the caret is visible while it's moving
  caretElm.style.animation = "none"
  caretElm.offsetWidth
  caretElm.style.animation = ""

  # One highlight rectangle per line of the selection
  rects = []
  if a < b
    for k in [lineIndexOf(a)..lineIndexOf(b)]
      ln = layout.lines[k]
      first = Math.max a, ln.start
      last = Math.min b - 1, ln.end
      continue if last < first
      p0 = caretPoint first
      x1 = if last + 1 <= ln.end then caretPoint(last + 1).x else caretPoint(last).x + pxPerInch / charactersPerInch
      rects.push "<div style='left:#{p0.x}px;top:#{p0.y}px;width:#{Math.max 2, x1 - p0.x}px;height:#{p0.h}px'></div>"
  selectionElm.innerHTML = rects.join ""
  renderFormatMenu()
  syncAlign()

# When the sheet is wider than the screen, it slides side to side like a carriage. Typing brings the strike
# point to the middle; clicking, tapping, and selecting leave the sheet where it is, so you can aim at it.
carriageX = 0
gutterL = 64 # room for the top & bottom margin tabs and the line space lever
gutterR = 16

sheetFits = ()-> geo.w * pxPerInch + gutterL + gutterR <= pagesElm.clientWidth

slideCarriage = (tx)->
  avail = pagesElm.clientWidth
  sheetW = geo.w * pxPerInch
  carriageX = Math.round if sheetFits() then (avail - sheetW) / 2 else clamp tx, avail - sheetW - gutterR, gutterL
  pagesElm.style.translate = "#{carriageX}px"

# Bring the strike point to the middle of the screen, and the line being typed above the machine
followCaret = ()->
  col = layout.pos[focusIndex()][2]
  slideCarriage pagesElm.clientWidth / 2 - col / charactersPerInch * pxPerInch
  renderFormatMenu()
  scrollCaretIntoView()

fmt = (v)-> +v.toFixed 2

# Keep the line being typed above the machine, like paper rolling up out of the platen
scrollCaretIntoView = ()->
  r = caretElm.getBoundingClientRect()
  limit = deckElm.getBoundingClientRect().top - 32
  if r.bottom > limit
    window.scrollBy 0, r.bottom - limit
  else if r.top < 48
    window.scrollBy 0, r.top - 48

# STYLES ##########################################################################################

saveStyles = ()->
  try localStorage.setItem "styles", styles

typingStyle = (center = false)-> styleCode settings.atlas, settings.red, center

# Keep the styles lined up with the text after every edit. The edit can't begin after where the
# selection started, which pins down where a repeated letter was inserted.
lastText = ""
editStart = 0
input.addEventListener "beforeinput", ()-> editStart = input.selectionStart

syncStyles = ()->
  text = input.value
  old = lastText
  limit = Math.min old.length, text.length, editStart
  p = 0
  p++ while p < limit and old[p] is text[p]
  s = 0
  s++ while s < Math.min(old.length, text.length) - p and old[old.length - 1 - s] is text[text.length - 1 - s]
  inserted = text.length - p - s
  # New letters take on the alignment of the paragraph they're typed into
  center = centeredAt old, styles, p
  styles = styles.slice(0, p) + typingStyle(center).repeat(inserted) + styles.slice(old.length - s)
  lastText = text
  saveStyles()

# Restyle the selected characters
restyle = (fn)->
  a = input.selectionStart
  b = input.selectionEnd
  return false unless a < b
  styles = styles.slice(0, a) + (fn c for c in styles.slice a, b).join("") + styles.slice(b)
  saveStyles()
  render()
  true

setWeight = (weight)-> restyle (c)-> styleCode weight, styleRed(c), styleCenter(c)
setRed = (red)-> restyle (c)-> styleCode styleWeight(c), red, styleCenter(c)

# Centre (or un-centre) every paragraph the selection touches — or just the one the caret is in
setCenter = (center)->
  text = input.value
  a = input.selectionStart
  b = input.selectionEnd
  b-- if b > a and text[b - 1] in breaks # A selection ending just after a carriage return stops at that line
  start = paragraphStart text, a
  start-- if start is text.length and start > 0 # An empty last line takes its alignment from the line before
  end = paragraphEnd text, b
  styles = styles.slice(0, start) + (styleCode styleWeight(c), styleRed(c), center for c in styles.slice start, end).join("") + styles.slice(end)
  settings.center = center if text.length is 0 # Nothing typed yet, so remember it for the first line
  saveStyles()
  save "settings", settings
  render()
  syncControls()

# A little menu that pops up over a selection, for striking it differently
renderFormatMenu = ()->
  a = input.selectionStart
  b = input.selectionEnd
  show = a < b and not pointer? and document.activeElement is input
  formatMenu.hidden = not show
  return unless show

  sel = styles.slice a, b
  for btn in formatMenu.querySelectorAll "[data-weight]"
    btn.classList.toggle "active", Array.from(sel).every (c)-> styleWeight(c) is btn.dataset.weight
  allRed = Array.from(sel).every styleRed
  formatMenu.querySelector("[data-red]").classList.toggle "active", allRed

  first = caretPoint a
  menuH = formatMenu.offsetHeight
  pageTop = pageViews[layout.pos[a][0]].elm.offsetTop
  top = if first.y - menuH - 10 > pageTop then first.y - menuH - 10 else caretPoint(Math.max a, b - 1).y + first.h + 10
  # Keep it on screen, wherever the carriage has slid to
  left = clamp first.x, 8 - carriageX, pagesElm.clientWidth - carriageX - formatMenu.offsetWidth - 8
  Object.assign formatMenu.style, left: left + "px", top: top + "px"

for btn in formatMenu.querySelectorAll "button"
  btn.addEventListener "pointerdown", (e)-> e.preventDefault() # Keep the selection while choosing
  do (btn)-> btn.onclick = ()->
    if btn.dataset.weight?
      setWeight btn.dataset.weight
    else
      setRed not btn.classList.contains "active"

# SETTINGS ########################################################################################

load = (name, def)->
  try
    JSON.parse(localStorage.getItem name) ? def
  catch
    def

saveText = ()->
  try localStorage.setItem "text", input.value

save = (name, val)->
  try localStorage.setItem name, JSON.stringify val
  val

settings = null

changeSettings = (changes)->
  Object.assign settings, changes
  normalize()
  save "settings", settings
  syncControls()
  invalidate()

# Keep the margins sane, whatever paper we're on
normalize = ()->
  settings.left = Math.max 0, Math.round settings.left
  settings.right = Math.max 0, Math.round settings.right
  settings.top = Math.max 0, Math.round settings.top
  settings.bottom = Math.max 0, Math.round settings.bottom
  settings.customW = clamp +settings.customW or 8.5, 1, 30
  settings.customH = clamp +settings.customH or 11, 1, 30
  settings.spacing = 1 unless settings.spacing in spacings
  settings.tabs = (Array.from new Set settings.tabs.map Math.round).sort (a, b)-> a - b

# Like the Olympia SM9's line space lever: single, one and a half, or double
spacings = [1, 1.5, 2]

controls = {}
controls[id] = $ "#" + id for id in ["red"]
atlasBtns = {}
atlasBtns[id] = $ "#" + id for id in weights
chooser = $ ".chooser"

# Flush left or centred, for the paragraph the caret is in
alignments = ["left", "center"]
alignLever = makeLever "align", alignments, ((a)-> linesIcon 4, a), ((a)-> setCenter a is "center")
alignLever.title = "Flush left or centred"
$("#red").after alignLever

syncAlign = ()->
  center = centeredAt input.value, styles, focusIndex()
  setLever alignLever, alignments, if center then "center" else "left"

paperName = ()->
  if settings.paper is "custom"
    "#{fmt settings.customW} × #{fmt settings.customH}"
  else
    papers[settings.paper].short + (if settings.landscape then " landscape" else "")

syncControls = ()->
  controls.red.checked = settings.red
  btn.classList.toggle "active", name is settings.atlas for name, btn of atlasBtns
  renderChooser() unless chooser.hidden
  null

# The strike & ribbon keys set how new letters are typed — and restyle the selection, if there is one
for name, btn of atlasBtns
  do (name)-> btn.onclick = ()->
    setWeight name
    changeSettings atlas: name
controls.red.onchange = ()->
  setRed controls.red.checked
  changeSettings red: controls.red.checked

# Hand the keyboard back to the page after pressing a key on the machine
for elm in document.querySelectorAll ".buttons button, .toggle"
  elm.addEventListener "click", ()-> input.focus preventScroll: true

$("#reset").onclick = ()->
  return unless confirm "Clear the page and reset the machine?"
  input.value = lastText = styles = ""
  saveText()
  saveStyles()
  settings = structuredClone defaults
  changeSettings {}
  input.focus()

# PAPER CHOOSER ###################################################################################

# Tap the paper size on the sheet, and every kind of paper is laid out on the desk, at true relative size.
# Pick one to feed it in.

chooserScale = 18 # CSS px per inch for the sheets on the desk

openChooser = ()->
  chooser.hidden = false
  document.body.classList.add "choosing"
  renderChooser()

closeChooser = ()->
  chooser.hidden = true
  document.body.classList.remove "choosing"
  input.focus preventScroll: true
  scrollCaretIntoView()

renderChooser = ()->
  for btn in chooser.querySelectorAll "[data-landscape]"
    btn.classList.toggle "active", btn.dataset.landscape is "#{settings.landscape}"
  sheets = chooser.querySelector ".sheets"
  sheets.innerHTML = ""
  for key, paper of papers
    do (key)->
      [w, h] = if key is "custom" then [settings.customW, settings.customH] else [paper.w, paper.h]
      [w, h] = [h, w] if settings.landscape and key isnt "custom"
      sheet = document.createElement "div"
      sheet.className = "sheet"
      sheet.classList.add "active" if key is settings.paper
      sheet.style.width = w * chooserScale + "px"
      sheet.style.height = h * chooserScale + "px"
      dims = if key is "custom" then "inches" else paper.name.split(" — ")[1]
      sheet.innerHTML = "<span class='name'>#{paper.short}</span><span class='dims'>#{dims}</span>"
      if key is "custom"
        size = document.createElement "span"
        size.className = "custom"
        for dim in ["customW", "customH"]
          do (dim)->
            field = document.createElement "input"
            field.type = "number"
            field.step = "0.25"
            field.min = 1
            field.max = 30
            field.value = settings[dim]
            field.onclick = (e)-> e.stopPropagation()
            field.onchange = ()->
              unless field.value is "" or isNaN +field.value
                Object.assign settings, "#{dim}": +field.value
                changeSettings paper: "custom"
            size.append field
            size.append " × " if dim is "customW"
        sheet.append size
      sheet.onclick = ()->
        changeSettings paper: key
        closeChooser()
      sheets.append sheet
  null

for btn in chooser.querySelectorAll "[data-landscape]"
  do (btn)-> btn.onclick = (e)->
    e.stopPropagation()
    changeSettings landscape: btn.dataset.landscape is "true"

chooser.onclick = (e)-> closeChooser() if e.target is chooser or e.target.matches ".sheets"
document.addEventListener "keydown", (e)-> closeChooser() if e.key is "Escape" and not chooser.hidden

# STOPS ###########################################################################################

# Margins & tab stops are set right on the sheet. The left & right margin tabs and the tab stops sit
# along the top edge: drag them, click the strip to set a tab, and pull a tab away to clear it.
# The top & bottom margin tabs sit along the left edge.

drag = null

showGuides = (show)-> document.body.classList.toggle "guides", show

pagesElm.addEventListener "pointerover", (e)-> showGuides true if e.target.closest ".strip, .vstop"
pagesElm.addEventListener "pointerout", (e)-> showGuides drag? if e.target.closest ".strip, .vstop"

colAt = (page, e)->
  rect = page.getBoundingClientRect()
  Math.round (e.clientX - rect.left) / pxPerInch * charactersPerInch

lineAt = (page, e)->
  rect = page.getBoundingClientRect()
  Math.round (e.clientY - rect.top) / pxPerInch * linesPerInch

startDrag = (e, handle, d)->
  e.preventDefault()
  e.stopPropagation()
  drag = d
  drag.y = e.clientY
  showGuides true
  handle.setPointerCapture e.pointerId
  handle.onpointermove = (e)-> moveDrag e
  handle.onpointerup = handle.onpointercancel = ()->
    handle.onpointermove = handle.onpointerup = handle.onpointercancel = null
    endDrag()

moveDrag = (e)->
  switch drag.kind
    when "left"
      col = colAt drag.page, e
      changeSettings left: clamp col, 0, geo.right - 1 unless col is geo.left
    when "right"
      col = colAt drag.page, e
      changeSettings right: geo.cols - clamp col, geo.left + 1, geo.cols unless col is geo.right
    when "tab"
      drag.removing = Math.abs(e.clientY - drag.y) > 30
      tabs = settings.tabs.slice()
      tabs[drag.index] = clamp colAt(drag.page, e), geo.left + 1, geo.right - 1
      Object.assign settings, {tabs}
      save "settings", settings
      invalidate()
    when "top"
      changeSettings top: clamp lineAt(drag.page, e), 0, geo.rows - geo.bottom - 1
    when "bottom"
      changeSettings bottom: clamp geo.rows - lineAt(drag.page, e), 0, geo.rows - geo.top - 1

endDrag = ()->
  tabs = settings.tabs.slice()
  tabs.splice drag.index, 1 if drag.kind is "tab" and drag.removing
  drag = null
  changeSettings {tabs}
  showGuides false

pagesElm.addEventListener "pointerdown", (e)->
  page = e.target.closest ".page"
  return unless page?
  if handle = e.target.closest ".vstop, .flag.down, .tabstop"
    startDrag e, handle, kind: handle.dataset.kind, index: +handle.dataset.index, page: page
  else if strip = e.target.closest ".strip"
    # Clicking an empty part of the strip sets a new tab stop
    col = colAt page, e
    return unless geo.left < col < geo.right
    changeSettings tabs: settings.tabs.concat col
    startDrag e, strip, kind: "tab", index: settings.tabs.indexOf(col), page: page
, true

# TYPING ##########################################################################################

# The hidden textarea holds the real text, selection, and undo history.
# Everything you see is drawn onto the pages — the textarea just catches keystrokes.

goalCol = null # Remember the column while moving up & down, like a real text editor

# follow: slide the carriage to the new strike point (for the keyboard, but not for pointing at the page)
setSelection = (anchor, focus, follow = true)->
  anchor = clamp anchor, 0, layout.n
  focus = clamp focus, 0, layout.n
  if focus < anchor
    input.setSelectionRange focus, anchor, "backward"
  else
    input.setSelectionRange anchor, focus, "forward"
  renderSelection()
  followCaret() if follow

getAnchorFocus = ()->
  if input.selectionDirection is "backward"
    [input.selectionEnd, input.selectionStart]
  else
    [input.selectionStart, input.selectionEnd]

insertText = (str)->
  # execCommand keeps the browser's undo history intact
  unless document.execCommand "insertText", false, str
    input.setRangeText str, input.selectionStart, input.selectionEnd, "end"
    input.dispatchEvent new Event "input"

moveVertically = (lines, extend)->
  [anchor, focus] = getAnchorFocus()
  k = lineIndexOf focus
  goalCol ?= layout.pos[focus][2]
  target = k + lines
  newFocus =
    if target < 0 then 0
    else if target >= layout.lines.length then layout.n
    else indexAtCol layout.lines[target], goalCol
  setSelection (if extend then anchor else newFocus), newFocus

moveToLineEdge = (end, extend)->
  [anchor, focus] = getAnchorFocus()
  ln = layout.lines[lineIndexOf focus]
  newFocus = if end then ln.end else ln.start
  setSelection (if extend then anchor else newFocus), newFocus

isMac = /Mac|iPhone|iPad/.test navigator.platform

input.addEventListener "keydown", (e)->
  mod = if isMac then e.metaKey else e.ctrlKey
  verticalKey = e.key in ["ArrowUp", "ArrowDown", "PageUp", "PageDown"]
  goalCol = null unless verticalKey

  if e.key is "Tab" and not (e.ctrlKey or e.metaKey or e.altKey)
    e.preventDefault()
    insertText "\t" unless e.shiftKey
  else if e.key is "Enter" and (e.metaKey or e.ctrlKey)
    e.preventDefault()
    insertText "\f" # Feed in a fresh sheet
  else if e.key is "ArrowUp" and not mod and not e.altKey
    e.preventDefault()
    moveVertically -1, e.shiftKey
  else if e.key is "ArrowDown" and not mod and not e.altKey
    e.preventDefault()
    moveVertically 1, e.shiftKey
  else if e.key is "PageUp"
    e.preventDefault()
    moveVertically -geo.linesPerPage, e.shiftKey
  else if e.key is "PageDown"
    e.preventDefault()
    moveVertically geo.linesPerPage, e.shiftKey
  else if e.key in ["Home", "End"] and not e.ctrlKey and not e.metaKey
    e.preventDefault()
    moveToLineEdge e.key is "End", e.shiftKey
  else if isMac and e.metaKey and e.key in ["ArrowLeft", "ArrowRight"]
    e.preventDefault()
    moveToLineEdge e.key is "ArrowRight", e.shiftKey
  else
    # Let the textarea handle it, then catch up
    requestAnimationFrame ()->
      renderSelection()
      followCaret()

input.addEventListener "input", ()->
  syncStyles()
  saveText()
  render()
  followCaret()

for type in ["select", "selectionchange", "keyup"]
  input.addEventListener type, ()-> renderSelection()
document.addEventListener "selectionchange", ()->
  renderSelection() if document.activeElement is input

updateFocus = ()-> document.body.classList.toggle "focused", document.activeElement is input
input.addEventListener "focus", updateFocus
input.addEventListener "blur", ()->
  updateFocus()
  renderFormatMenu()

# POINTER #########################################################################################

# Turn a pointer position into an index in the text
hitTest = (e)->
  return layout.n unless pageViews.length
  # Find the page under the pointer, or the nearest one
  best = 0
  for view, p in pageViews
    rect = view.elm.getBoundingClientRect()
    best = p if e.clientY >= rect.top - 16
  rect = pageViews[best].elm.getBoundingClientRect()
  x = (e.clientX - rect.left) / pxPerInch
  y = (e.clientY - rect.top) / pxPerInch
  indexAtPoint geo, best, x, y

# Grow a click into the word (double click) or line (triple click) around it
expand = (i, detail)->
  text = layout.text
  if detail is 2
    # A word is letters, numbers, and apostrophes — or, between words, a run of punctuation
    word = /[\p{L}\p{N}'’]/u
    a = b = i
    a = i - 1 if i > 0 and not word.test(text[i] ? "") and word.test text[i - 1]
    kind = if word.test(text[a] ? "") then word else /[^\s\p{L}\p{N}'’]/u
    a-- while a > 0 and kind.test text[a - 1]
    b = a
    b++ while b < text.length and kind.test text[b]
    [a, b]
  else
    ln = layout.lines[lineIndexOf i]
    [ln.start, Math.min ln.end + 1, layout.n]

pointer = null

# PointerEvent.detail isn't reliable across browsers, so count multi-clicks ourselves
lastClick = time: 0, x: 0, y: 0, count: 0
clickCount = (e)->
  near = Math.hypot(e.clientX - lastClick.x, e.clientY - lastClick.y) < (if e.pointerType is "touch" then 24 else 6)
  quick = e.timeStamp - lastClick.time < 450
  lastClick = time: e.timeStamp, x: e.clientX, y: e.clientY, count: if near and quick then lastClick.count % 3 + 1 else 1
  lastClick.count

pagesElm.addEventListener "pointerdown", (e)->
  return unless e.target.closest ".page"
  return if e.target.closest ".paper-label, .strip, .vstop, .lever"
  return if e.button isnt 0

  # On touch screens, a tap places the carriage, a sideways swipe slides the sheet, and an up-down drag scrolls
  if e.pointerType is "touch"
    pointer = touch: true, x: e.clientX, y: e.clientY, tx: carriageX, sliding: false
    return

  e.preventDefault()
  input.focus preventScroll: true
  i = hitTest e
  goalCol = null
  count = clickCount e
  if count >= 2
    [a, b] = expand i, count
    setSelection a, b, false
    pointer = anchor: a
  else
    [anchor] = getAnchorFocus()
    anchor = i unless e.shiftKey
    setSelection anchor, i, false
    pointer = {anchor}
  pagesElm.setPointerCapture e.pointerId

pagesElm.addEventListener "pointermove", (e)->
  return unless pointer?
  if pointer.touch
    dx = e.clientX - pointer.x
    if not pointer.sliding and Math.abs(dx) > 8 and Math.abs(dx) > Math.abs(e.clientY - pointer.y)
      pointer.sliding = true
      pagesElm.classList.add "sliding"
    slideCarriage pointer.tx + dx if pointer.sliding
  else
    setSelection pointer.anchor, hitTest(e), false

pagesElm.addEventListener "pointerup", (e)->
  if pointer?.touch and not pointer.sliding and Math.hypot(e.clientX - pointer.x, e.clientY - pointer.y) < 10
    pointer = null
    input.focus preventScroll: true
    goalCol = null
    i = hitTest e
    count = clickCount e
    if count >= 2 then setSelection expand(i, count)..., false else setSelection i, i, false
  pointer = null
  pagesElm.classList.remove "sliding"
  renderFormatMenu()

# Mobile browsers follow a tap with a pretend mousedown that would pull focus off the page — stop it
pagesElm.addEventListener "mousedown", (e)->
  e.preventDefault() if e.target.closest(".page") and not e.target.closest(".paper-label")

pagesElm.addEventListener "pointercancel", ()->
  pointer = null
  pagesElm.classList.remove "sliding"

window.addEventListener "resize", ()-> render()

# SAVE & PRINT ####################################################################################

renderPageAtExportSize = (p)->
  canvas = document.createElement "canvas"
  canvas.width = Math.round geo.w * exportDPI
  canvas.height = Math.round geo.h * exportDPI
  drawPage canvas.getContext("2d"), p, exportDPI
  canvas

toBlob = (canvas)-> new Promise (resolve)-> canvas.toBlob resolve, "image/png"

$("#download").onclick = ()->
  for _, p in layout.pages
    blob = await toBlob renderPageAtExportSize p
    link = document.createElement "a"
    link.href = URL.createObjectURL blob
    link.download = if layout.pages.length is 1 then "senatorial.png" else "senatorial-page-#{p + 1}.png"
    link.click()
    setTimeout ((url)-> ()-> URL.revokeObjectURL url)(link.href), 1000
  null

$("#print").onclick = ()->
  printElm = $ ".print"
  printElm.innerHTML = ""
  style = document.createElement "style"
  style.textContent = "@page { size: #{geo.w}in #{geo.h}in; margin: 0; }"
  printElm.append style
  for _, p in layout.pages
    img = new Image()
    img.src = URL.createObjectURL await toBlob renderPageAtExportSize p
    img.style.width = "#{geo.w}in"
    img.style.height = "#{geo.h}in"
    await img.decode()
    printElm.append img
  window.print()

# GO ##############################################################################################

settings = Object.assign structuredClone(defaults), load "settings", {}
normalize()

input.value = lastText = (try localStorage.getItem "text") ? ""

# Text from before styles were kept per character is all in the machine's current style
styles = (try localStorage.getItem "styles") ? ""
styles = typingStyle().repeat input.value.length unless styles.length is input.value.length and /^[0-9ab]*$/.test styles

syncControls()
loadAtlases()
render()
input.focus preventScroll: true
input.setSelectionRange layout.n, layout.n
renderSelection()
updateFocus()
followCaret()
