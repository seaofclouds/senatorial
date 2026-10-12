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
  letter: name: "US Letter — 8½ × 11", w: 8.5, h: 11
  legal: name: "US Legal — 8½ × 14", w: 8.5, h: 14
  halfLetter: name: "Half Letter — 5½ × 8½", w: 5.5, h: 8.5
  executive: name: "Executive — 7¼ × 10½", w: 7.25, h: 10.5
  a4: name: "A4 — 210 × 297 mm", w: mm(210), h: mm(297)
  a5: name: "A5 — 148 × 210 mm", w: mm(148), h: mm(210)
  a6: name: "A6 — 105 × 148 mm", w: mm(105), h: mm(148)
  card3x5: name: "Index Card — 5 × 3", w: 5, h: 3
  card4x6: name: "Index Card — 6 × 4", w: 6, h: 4
  card5x8: name: "Index Card — 8 × 5", w: 8, h: 5
  custom: name: "Custom…"

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
  zoom: "fit"
  guides: true

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

desk = $ ".desk"
column = $ ".column"
pagesElm = $ ".pages"
selectionElm = $ ".selection"
caretElm = $ ".caret"
input = $ ".input"
rulerElm = $ ".ruler"
rulerCanvas = $ ".ruler canvas"
rulerCtx = rulerCanvas.getContext "2d"

pageViews = []
renderVersion = 0
geo = null
zoom = 1
pxPerInch = cssDPI

# Settings changed or the atlas loaded, so every page needs to be redrawn
invalidate = ()->
  renderVersion++
  render()

currentZoom = (g)->
  return +settings.zoom unless settings.zoom is "fit"
  available = desk.clientWidth - 32
  clamp available / (g.w * cssDPI), .25, 2

makePageView = ()->
  elm = document.createElement "div"
  elm.className = "page"
  canvas = document.createElement "canvas"
  guide = document.createElement "div"
  guide.className = "guide"
  elm.append canvas, guide
  pagesElm.insertBefore elm, selectionElm
  {elm, canvas, guide, ctx: canvas.getContext("2d"), key: null}

render = ()->
  return unless settings?
  geo = g = geometry()
  doLayout g
  zoom = currentZoom g
  pxPerInch = cssDPI * zoom
  cssW = g.w * pxPerInch
  cssH = g.h * pxPerInch
  dpr = window.devicePixelRatio or 1

  pageViews.push makePageView() while pageViews.length < layout.pages.length
  pageViews.pop().elm.remove() while pageViews.length > layout.pages.length

  for view, p in pageViews
    view.elm.dataset.page = "#{p + 1}"
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
      height: ((g.linesPerPage - 1) * g.spacing + 1) / linesPerInch * pxPerInch + "px"

    # Only redraw pages whose contents actually changed
    {start, end} = layout.pages[p]
    key = "#{renderVersion}|#{pw}|#{layout.text.slice start, end}"
    unless view.key is key
      view.key = key
      drawPage view.ctx, p, pw / g.w

  drawRuler g, cssW
  renderSelection()
  updateStatus()

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

# The ruler is laid out just like the typewriter's paper scale: one tick per column, numbered from the left edge of the sheet
drawRuler = (g, cssW)->
  dpr = window.devicePixelRatio or 1
  cssH = rulerElm.offsetHeight
  rulerElm.style.width = cssW + "px"
  rulerCanvas.width = Math.round cssW * dpr
  rulerCanvas.height = Math.round cssH * dpr
  ctx = rulerCtx
  ctx.setTransform dpr, 0, 0, dpr, 0, 0
  step = cssW / (g.w * charactersPerInch)

  ctx.fillStyle = "hsl(18, 4%, 24%)"
  ctx.fillRect 0, 0, cssW, cssH
  ctx.fillStyle = "hsl(30, 5%, 33%)"
  ctx.fillRect g.left * step, 0, (g.right - g.left) * step, cssH

  ctx.font = "9px system-ui"
  ctx.textAlign = "center"
  ctx.textBaseline = "top"
  labelEvery = if step * 10 >= 18 then 10 else 20
  for i in [0..g.cols]
    inside = g.left <= i <= g.right
    height = if i % 10 is 0 then 11 else if i % 5 is 0 then 7 else 4
    continue if step < 3 and i % 5 isnt 0
    ctx.fillStyle = if inside then "hsl(38, 6%, 72%)" else "hsl(38, 4%, 48%)"
    ctx.fillRect Math.round(i * step) - .5, cssH - height, 1, height
    if i % labelEvery is 0 and i > 0 and i < g.cols
      ctx.fillText i, i * step, 3

  # Default tab stops are shown as little dots
  unless settings.tabs.length
    ctx.fillStyle = "hsl(38, 6%, 62%)"
    for c in defaultTabs g
      ctx.beginPath()
      ctx.arc c * step, cssH - 14, 1.5, 0, Math.PI * 2
      ctx.fill()

  # Sync the draggable stops
  stops = [{kind: "left", col: g.left}, {kind: "right", col: g.right}]
  stops.push {kind: "tab", col, index} for col, index in settings.tabs
  elms = Array.from rulerElm.querySelectorAll ".stop"
  while elms.length < stops.length
    elms.push e = document.createElement "div"
    rulerElm.append e
  e.remove() for e in elms.splice stops.length
  for stop, k in stops
    e = elms[k]
    e.className = "stop " + (if stop.kind is "tab" then "tab" else "margin")
    e.classList.add "removing" if drag?.kind is "tab" and drag.index is stop.index and drag.removing
    e.dataset.kind = stop.kind
    e.dataset.index = stop.index ? ""
    e.style.left = stop.col * step + "px"
    e.title = if stop.kind is "tab" then "Tab stop at #{stop.col}" else "#{stop.kind[0].toUpperCase() + stop.kind[1..]} margin at #{stop.col}"
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
  focus = if input.selectionDirection is "backward" then a else b
  c = caretPoint Math.min focus, layout.n
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

updateStatus = ()->
  i = Math.min (if input.selectionDirection is "backward" then input.selectionStart else input.selectionEnd), layout.n
  [page, line, col] = layout.pos[i]
  $("#status").textContent = "Page #{page + 1} of #{layout.pages.length} · Line #{line + 1} of #{geo.linesPerPage} · Column #{col}"
  $("#sheet").textContent = "#{fmt geo.w} × #{fmt geo.h} in · #{geo.right - geo.left} characters × #{geo.linesPerPage} lines"

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
  renderSelection()

# Keep the margins sane, whatever paper we're on
normalize = ()->
  settings.left = Math.max 0, Math.round settings.left
  settings.right = Math.max 0, Math.round settings.right
  settings.top = Math.max 0, Math.round settings.top
  settings.bottom = Math.max 0, Math.round settings.bottom
  settings.customW = clamp +settings.customW or 8.5, 1, 30
  settings.customH = clamp +settings.customH or 11, 1, 30
  settings.tabs = (Array.from new Set settings.tabs.map Math.round).sort (a, b)-> a - b

controls = {}
controls[id] = $ "#" + id for id in ["paper", "orientation", "customSize", "customW", "customH", "left", "right", "top", "bottom", "spacing", "zoom", "guides", "red"]
atlasBtns = {}
atlasBtns[id] = $ "#" + id for id in ["regular", "light", "double"]

for key, paper of papers
  option = document.createElement "option"
  option.value = key
  option.textContent = paper.name
  controls.paper.append option

syncControls = ()->
  g = geometry()
  controls.paper.value = settings.paper
  controls.customSize.hidden = settings.paper isnt "custom"
  controls.orientation.textContent = if settings.landscape then "Landscape" else "Portrait"
  sync = (elm, value)-> elm.value = value unless document.activeElement is elm
  sync controls.customW, settings.customW
  sync controls.customH, settings.customH
  sync controls.left, g.left
  sync controls.right, g.right
  sync controls.top, g.top
  sync controls.bottom, g.bottom
  controls.left.max = g.right - 1
  controls.right.max = g.cols
  controls.left.parentElement.title = "Left margin stop: column #{g.left} (#{fmt g.left / charactersPerInch} in from the edge)"
  controls.right.parentElement.title = "Right margin stop: column #{g.right} (#{fmt (g.cols - g.right) / charactersPerInch} in from the edge)"
  controls.top.parentElement.title = "Top margin: #{g.top} lines (#{fmt g.top / linesPerInch} in)"
  controls.bottom.parentElement.title = "Bottom margin: #{g.bottom} lines (#{fmt g.bottom / linesPerInch} in)"
  controls.spacing.value = settings.spacing
  controls.zoom.value = settings.zoom
  controls.guides.checked = settings.guides
  controls.red.checked = settings.red
  document.body.classList.toggle "guides", settings.guides
  btn.classList.toggle "active", name is settings.atlas for name, btn of atlasBtns
  null

numberInput = (elm, cb)->
  elm.oninput = ()-> cb +elm.value unless elm.value is "" or isNaN +elm.value
  elm.onchange = ()-> syncControls()

controls.paper.onchange = ()-> changeSettings paper: controls.paper.value
controls.orientation.onclick = ()-> changeSettings landscape: not settings.landscape
numberInput controls.customW, (v)-> changeSettings customW: v
numberInput controls.customH, (v)-> changeSettings customH: v
numberInput controls.left, (v)-> changeSettings left: v
numberInput controls.right, (v)-> changeSettings right: geometry().cols - v
numberInput controls.top, (v)-> changeSettings top: v
numberInput controls.bottom, (v)-> changeSettings bottom: v
controls.spacing.onchange = ()-> changeSettings spacing: +controls.spacing.value
controls.zoom.onchange = ()-> changeSettings zoom: controls.zoom.value
controls.guides.onchange = ()-> changeSettings guides: controls.guides.checked
controls.red.onchange = ()-> changeSettings red: controls.red.checked
for name, btn of atlasBtns
  do (name)-> btn.onclick = ()-> changeSettings atlas: name
$("#clearTabs").onclick = ()-> changeSettings tabs: []

# Hand the keyboard back to the page after clicking a button or picking from a menu
for elm in document.querySelectorAll "header button, header select, footer select, header .toggle, footer input"
  do (elm)->
    elm.addEventListener "change", ()-> input.focus preventScroll: true
    elm.addEventListener "click", ()-> input.focus preventScroll: true if elm.tagName is "BUTTON"

$("#reset").onclick = ()->
  return unless confirm "Clear the page and reset all settings?"
  input.value = ""
  saveText()
  settings = structuredClone defaults
  changeSettings {}
  loadAtlas()
  input.focus()

# RULER INTERACTION ###############################################################################

drag = null

rulerCol = (e)->
  rect = rulerElm.getBoundingClientRect()
  Math.round (e.clientX - rect.left) / rect.width * geo.w * charactersPerInch

rulerElm.onpointerdown = (e)->
  e.preventDefault()
  col = rulerCol e
  stop = e.target.closest ".stop"
  if stop?
    drag = kind: stop.dataset.kind, index: +stop.dataset.index
  else
    # Clicking on an empty part of the ruler sets a new tab stop
    return unless geo.left < col < geo.right
    tabs = settings.tabs.concat col
    changeSettings {tabs}
    drag = kind: "tab", index: settings.tabs.indexOf col
  drag.y = e.clientY
  rulerElm.setPointerCapture e.pointerId

rulerElm.onpointermove = (e)->
  return unless drag?
  col = rulerCol e
  switch drag.kind
    when "left"
      changeSettings left: clamp col, 0, geo.right - 1 unless col is geo.left
    when "right"
      changeSettings right: geo.cols - clamp col, geo.left + 1, geo.cols unless col is geo.right
    when "tab"
      # Pull a tab stop off the ruler to clear it
      drag.removing = Math.abs(e.clientY - drag.y) > 30
      tabs = settings.tabs.slice()
      tabs[drag.index] = clamp col, geo.left + 1, geo.right - 1
      Object.assign settings, {tabs}
      save "settings", settings
      invalidate()

rulerElm.onpointerup = rulerElm.onpointercancel = (e)->
  return unless drag?
  if drag.kind is "tab"
    tabs = settings.tabs.slice()
    tabs.splice drag.index, 1 if drag.removing
    drag = null
    changeSettings {tabs}
  drag = null

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
  updateStatus()
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
      updateStatus()

input.addEventListener "input", ()->
  saveText()
  render()
  scrollCaretIntoView()

for type in ["select", "selectionchange", "keyup"]
  input.addEventListener type, ()->
    renderSelection()
    updateStatus()
document.addEventListener "selectionchange", ()->
  if document.activeElement is input
    renderSelection()
    updateStatus()

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
