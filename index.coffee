# TYPE SCALE ######################################################################################

# Everything is measured in real-world inches, so pages come out at their true physical size
charactersPerInch = 11 # this is based on the actual typewriter
linesPerInch = 6 # standard typewriter line feed — single spacing is 1/6"
atlasDPI = 1200 # ROUGHLY — this is based on the glyph scan Todd sent me
exportDPI = 600 # Resolution of saved & printed pages. Change it to whatever you want, and everything Just Works™
cssDPI = 96 # CSS pixels per inch at 100% zoom

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

# This image stores the currently-loaded glyph atlas
atlasImg = null

loadAtlas = ()->
  src = settings.atlas + (if settings.red then "-red" else "")
  src = "regular-red" if src is "double-red"
  img = new Image()
  img.src = "glyphs/#{src}.png"
  img.onload = ()->
    atlasImg = img
    invalidate()
    document.body.classList.add "ready"

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
      lines.push {page, line, start: i, end: i}

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

section = $ "section"
pagesElm = $ ".pages"
selectionElm = $ ".selection"
caretElm = $ ".caret"
input = $ ".input"
scaleElm = $ ".scale"
scaleCanvas = $ ".scale canvas"
scaleCtx = scaleCanvas.getContext "2d"
pointerElm = $ ".pointer"

pageViews = []
renderVersion = 0
geo = null
pxPerInch = cssDPI

# Settings changed or the atlas loaded, so every page needs to be redrawn
invalidate = ()->
  renderVersion++
  render()

# Every sheet is shown at the same scale — a letter-width sheet fills the machine,
# and smaller sheets (like index cards) look smaller, just like they would in the carriage
widestUsualSheet = 8.5
currentZoom = (g)->
  gutter = if window.innerWidth < 700 then 40 else 128
  available = section.clientWidth - gutter
  available / (Math.max(g.w, widestUsualSheet) * cssDPI)

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
  top = document.createElement "div"
  top.className = "pill vstop"
  top.dataset.kind = "top"
  bottom = document.createElement "div"
  bottom.className = "pill vstop"
  bottom.dataset.kind = "bottom"
  elm.append canvas, guide, label, top, bottom
  pagesElm.insertBefore elm, selectionElm
  {elm, canvas, guide, label, top, bottom, ctx: canvas.getContext("2d"), key: null}

render = ()->
  return unless settings?
  geo = g = geometry()
  doLayout g
  pxPerInch = cssDPI * currentZoom g
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

    # Only redraw pages whose contents actually changed
    {start, end} = layout.pages[p]
    key = "#{renderVersion}|#{pw}|#{layout.text.slice start, end}"
    unless view.key is key
      view.key = key
      drawPage view.ctx, p, pw / g.w

  drawScale g, cssW
  renderSelection()

# Draw one page onto a canvas, at the given pixels per inch (screen, or exportDPI for saving)
drawPage = (ctx, p, ppi)->
  ctx.setTransform 1, 0, 0, 1, 0, 0
  ctx.globalCompositeOperation = "source-over"
  ctx.fillStyle = "#fff"
  ctx.fillRect 0, 0, ctx.canvas.width, ctx.canvas.height
  return unless atlasImg?

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
    [gx, gy] = glyph c
    [_, line, col] = layout.pos[i]
    px = col * gw
    py = lineTop(geo, line) * atlasDPI + verticalAlign
    ctx.drawImage atlasImg, gx - pad, gy - pad, gw + pad*2, gh + pad*2, px - pad, py - pad, gw + pad*2, gh + pad*2
  null

# The scale runs across the sheet, one tick per column, just like the typewriter's paper scale
drawScale = (g, cssW)->
  dpr = window.devicePixelRatio or 1
  cssH = scaleElm.offsetHeight
  scaleElm.style.width = cssW + "px"
  scaleCanvas.width = Math.round cssW * dpr
  scaleCanvas.height = Math.round cssH * dpr
  ctx = scaleCtx
  ctx.setTransform dpr, 0, 0, dpr, 0, 0
  ctx.clearRect 0, 0, cssW, cssH
  step = cssW / (g.w * charactersPerInch)

  # The space between the margins is outlined, like the original scale
  ctx.beginPath()
  ctx.roundRect g.left * step, -6, (g.right - g.left) * step, cssH + 6, 5
  ctx.strokeStyle = "hsl(18, 4%, 19%)"
  ctx.lineWidth = 2
  ctx.stroke()

  for i in [0..g.cols]
    continue if i is g.left or i is g.right
    continue if step < 4 and i % 5 isnt 0
    ctx.fillStyle =
      if not (g.left < i < g.right) then "hsl(18, 4%, 25%)"
      else if i % 10 is 0 then "hsl(18, 2%, 55%)"
      else "hsl(18, 2%, 45%)"
    height = if i % 10 is 0 then 17 else if i % 5 is 0 then 12 else 7
    ctx.fillRect Math.round(i * step) - 1, 0, 2, height

  # Sync the draggable stops: two margin pills and a notch for each tab stop
  stops = [{kind: "left", col: g.left}, {kind: "right", col: g.right}]
  stops.push {kind: "tab", col, index} for col, index in settings.tabs
  elms = Array.from scaleElm.querySelectorAll ".pill, .tab"
  while elms.length < stops.length
    elms.push e = document.createElement "div"
    scaleElm.append e
  e.remove() for e in elms.splice stops.length
  for stop, k in stops
    e = elms[k]
    e.className = if stop.kind is "tab" then "tab" else "pill"
    e.classList.toggle "removing", drag?.kind is "tab" and drag.index is stop.index and drag.removing
    e.classList.toggle "dragging", drag?.kind is stop.kind
    e.dataset.kind = stop.kind
    e.dataset.index = stop.index ? ""
    e.style.left = stop.col * step + "px"
    e.textContent = if stop.kind is "tab" then "" else stop.col
    e.title =
      if stop.kind is "tab" then "Tab stop at #{stop.col} — drag it off the scale to clear it"
      else if stop.kind is "left" then "Left margin at #{stop.col} (#{fmt stop.col / charactersPerInch} in)"
      else "Right margin at #{stop.col} (#{fmt (g.cols - stop.col) / charactersPerInch} in from the edge) · #{g.right - g.left} characters per line"
  null

# Caret position for index i, in CSS px relative to the .pages container
caretPoint = (i)->
  [page, line, col] = layout.pos[i]
  view = pageViews[page]
  x: view.elm.offsetLeft + col / charactersPerInch * pxPerInch
  y: view.elm.offsetTop + lineTop(geo, line) * pxPerInch
  h: pxPerInch / linesPerInch

renderSelection = ()->
  return unless layout? and pageViews.length
  a = input.selectionStart
  b = input.selectionEnd

  # Caret goes on the moving end of the selection
  focus = Math.min (if input.selectionDirection is "backward" then a else b), layout.n
  c = caretPoint focus
  Object.assign caretElm.style, left: c.x - 1 + "px", top: c.y + "px", height: c.h + "px"
  Object.assign input.style, left: c.x + "px", top: c.y + "px", height: c.h + "px"

  # The pointer on the scale follows the carriage
  pointerElm.style.left = layout.pos[focus][2] / charactersPerInch * pxPerInch + "px"

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

fmt = (v)-> +v.toFixed 2

scrollCaretIntoView = ()-> caretElm.scrollIntoView block: "nearest", inline: "nearest"

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
  loadAtlas() if changes.atlas? or changes.red?
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
controls[id] = $ "#" + id for id in ["spacing", "red", "customW", "customH"]
atlasBtns = {}
atlasBtns[id] = $ "#" + id for id in ["regular", "light", "double"]
chooser = $ ".chooser"

# Engrave each lever position with three little lines, spaced the way that setting feeds the paper
spacingBtns = for s in spacings
  do (s)->
    gap = 3 * s
    btn = document.createElement "button"
    btn.title = "#{if s is 1 then "Single" else if s is 2 then "Double" else "1½"} spacing"
    btn.innerHTML = "<svg viewBox='0 0 20 20'>" + ("<line x1='5' x2='15' y1='#{10 + k * gap}' y2='#{10 + k * gap}'/>" for k in [-1..1]).join("") + "</svg>"
    btn.onclick = ()-> changeSettings spacing: s
    controls.spacing.append btn
    btn

paperName = ()->
  if settings.paper is "custom"
    "#{fmt settings.customW} × #{fmt settings.customH}"
  else
    papers[settings.paper].short + (if settings.landscape then " landscape" else "")

syncControls = ()->
  k = Math.max 0, spacings.indexOf settings.spacing
  controls.spacing.style.setProperty "--position", k
  btn.classList.toggle "active", i is k for btn, i in spacingBtns
  controls.red.checked = settings.red
  btn.classList.toggle "active", name is settings.atlas for name, btn of atlasBtns
  renderChooser() unless chooser.hidden
  null

for name, btn of atlasBtns
  do (name)-> btn.onclick = ()-> changeSettings atlas: name
controls.red.onchange = ()-> changeSettings red: controls.red.checked
$("#clearTabs").onclick = ()-> changeSettings tabs: []

# Hand the keyboard back to the page after pressing a key on the machine
for elm in document.querySelectorAll ".buttons button, .toggle"
  elm.addEventListener "click", ()-> input.focus preventScroll: true

$("#reset").onclick = ()->
  return unless confirm "Clear the page and reset the machine?"
  input.value = ""
  saveText()
  settings = structuredClone defaults
  changeSettings {}
  loadAtlas()
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

# Margin & tab stops are set the way you would on the machine: drag the stops along the scale,
# click the scale to set a tab, and pull a tab off the scale to clear it.
# The top & bottom margin stops sit along the left edge of each sheet.

drag = null

showGuides = (show)-> document.body.classList.toggle "guides", show
scaleElm.onpointerenter = ()-> showGuides true
scaleElm.onpointerleave = ()-> showGuides drag?

scaleCol = (e)->
  rect = scaleElm.getBoundingClientRect()
  Math.round (e.clientX - rect.left) / rect.width * geo.w * charactersPerInch

scaleElm.onpointerdown = (e)->
  e.preventDefault()
  col = scaleCol e
  stop = e.target.closest ".pill, .tab"
  if stop?
    drag = kind: stop.dataset.kind, index: +stop.dataset.index
  else
    # Clicking on an empty part of the scale sets a new tab stop
    return unless geo.left < col < geo.right
    tabs = settings.tabs.concat col
    changeSettings {tabs}
    drag = kind: "tab", index: settings.tabs.indexOf col
  drag.y = e.clientY
  showGuides true
  scaleElm.setPointerCapture e.pointerId

scaleElm.onpointermove = (e)->
  return unless drag?
  col = scaleCol e
  switch drag.kind
    when "left"
      changeSettings left: clamp col, 0, geo.right - 1 unless col is geo.left
    when "right"
      changeSettings right: geo.cols - clamp col, geo.left + 1, geo.cols unless col is geo.right
    when "tab"
      # Pull a tab stop off the scale to clear it
      drag.removing = Math.abs(e.clientY - drag.y) > 30
      tabs = settings.tabs.slice()
      tabs[drag.index] = clamp col, geo.left + 1, geo.right - 1
      Object.assign settings, {tabs}
      save "settings", settings
      invalidate()

scaleElm.onpointerup = scaleElm.onpointercancel = (e)->
  return unless drag?
  tabs = settings.tabs.slice()
  tabs.splice drag.index, 1 if drag.kind is "tab" and drag.removing
  drag = null
  changeSettings {tabs}
  showGuides scaleElm.matches ":hover"

# Top & bottom margin stops
pagesElm.addEventListener "pointerdown", (e)->
  stop = e.target.closest ".vstop"
  return unless stop?
  e.preventDefault()
  e.stopPropagation()
  drag = kind: stop.dataset.kind, page: stop.closest ".page"
  stop.classList.add "dragging"
  showGuides true
  stop.setPointerCapture e.pointerId
  stop.onpointermove = (e)->
    rect = drag.page.getBoundingClientRect()
    line = Math.round (e.clientY - rect.top) / pxPerInch * linesPerInch
    if drag.kind is "top"
      changeSettings top: clamp line, 0, geo.rows - geo.bottom - 1
    else
      changeSettings bottom: clamp geo.rows - line, 0, geo.rows - geo.top - 1
  stop.onpointerup = stop.onpointercancel = ()->
    stop.onpointermove = stop.onpointerup = stop.onpointercancel = null
    stop.classList.remove "dragging"
    drag = null
    showGuides false
, true

# TYPING ##########################################################################################

# The hidden textarea holds the real text, selection, and undo history.
# Everything you see is drawn onto the pages — the textarea just catches keystrokes.

goalCol = null # Remember the column while moving up & down, like a real text editor

setSelection = (anchor, focus)->
  anchor = clamp anchor, 0, layout.n
  focus = clamp focus, 0, layout.n
  if focus < anchor
    input.setSelectionRange focus, anchor, "backward"
  else
    input.setSelectionRange anchor, focus, "forward"
  renderSelection()
  scrollCaretIntoView()

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
    
input.addEventListener "input", ()->
  saveText()
  render()
  scrollCaretIntoView()

for type in ["select", "selectionchange", "keyup"]
  input.addEventListener type, ()->
    renderSelection()
  document.addEventListener "selectionchange", ()->
  if document.activeElement is input
    renderSelection()
  
updateFocus = ()-> document.body.classList.toggle "focused", document.activeElement is input
input.addEventListener "focus", updateFocus
input.addEventListener "blur", updateFocus

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
    a = b = i
    a-- while a > 0 and /\S/.test text[a - 1]
    b++ while b < text.length and /\S/.test text[b]
    [a, b]
  else
    ln = layout.lines[lineIndexOf i]
    [ln.start, Math.min ln.end + 1, layout.n]

pointer = null

# PointerEvent.detail isn't reliable across browsers, so count multi-clicks ourselves
lastClick = time: 0, x: 0, y: 0, count: 0
clickCount = (e)->
  near = Math.hypot(e.clientX - lastClick.x, e.clientY - lastClick.y) < 6
  quick = e.timeStamp - lastClick.time < 450
  lastClick = time: e.timeStamp, x: e.clientX, y: e.clientY, count: if near and quick then lastClick.count % 3 + 1 else 1
  lastClick.count

pagesElm.addEventListener "pointerdown", (e)->
  return unless e.target.closest ".page"
  return if e.target.closest ".paper-label"
  return if e.button isnt 0

  # On touch screens, a tap places the carriage, and a drag scrolls
  if e.pointerType is "touch"
    pointer = touch: true, x: e.clientX, y: e.clientY
    return

  e.preventDefault()
  input.focus preventScroll: true
  i = hitTest e
  goalCol = null
  count = clickCount e
  if count >= 2
    [a, b] = expand i, count
    setSelection a, b
    pointer = anchor: a
  else
    [anchor] = getAnchorFocus()
    anchor = i unless e.shiftKey
    setSelection anchor, i
    pointer = {anchor}
  pagesElm.setPointerCapture e.pointerId

pagesElm.addEventListener "pointermove", (e)->
  return unless pointer? and not pointer.touch
  setSelection pointer.anchor, hitTest e

pagesElm.addEventListener "pointerup", (e)->
  if pointer?.touch and Math.hypot(e.clientX - pointer.x, e.clientY - pointer.y) < 10
    input.focus preventScroll: true
    goalCol = null
    i = hitTest e
    setSelection i, i
  pointer = null

pagesElm.addEventListener "pointercancel", ()-> pointer = null

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

input.value = (try localStorage.getItem "text") ? ""

syncControls()
loadAtlas()
render()
input.focus preventScroll: true
input.setSelectionRange layout.n, layout.n
renderSelection()
updateFocus()
scrollCaretIntoView()
