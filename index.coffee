# TYPE SCALE ######################################################################################

# Everything is measured in real-world inches, so pages come out at their true physical size
charactersPerInch = 11 # this is based on the actual typewriter
linesPerInch = 6 # standard typewriter line feed — single spacing is 1/6"
atlasDPI = 600 # the glyph images' resolution (glyphs/layout.json)
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
  b6jis: short: "B6 JIS", name: "B6 (JIS) — 128 × 182 mm", w: mm(128), h: mm(182)
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
  linkLeftRight: false # when linked, the left & right margins mirror each other
  linkTopBottom: false # and the same for the top & bottom
  tabs: [] # tab stops, in columns from the left edge of the paper. When empty, there's a stop every 5 columns.

defaultTabInterval = 5

clamp = (v, lo, hi)-> Math.max lo, Math.min hi, v

# The size of the paper that's in, in inches, the way it's usually fed
paperSize = ()->
  if settings.paper is "custom" then [settings.customW, settings.customH]
  else
    {w, h} = papers[settings.paper] ? papers.letter
    [w, h]

# Margins to suit the paper: a quarter inch all round on a card, growing along a gentle curve with the sheet's short
# side to an inch on letter and anything wider
paperMargins = (w, h)->
  t = clamp (Math.min(w, h) - 4) / 4.5, 0, 1
  inches = 0.25 + 0.75 * t ** 1.5
  cols = Math.round inches * charactersPerInch
  lines = Math.round inches * linesPerInch
  {left: cols, right: cols, top: lines, bottom: lines}

# Work out the character grid for the current sheet
geometry = ()->
  [w, h] = paperSize()
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

# Each strike & ribbon colour has an image of every glyph, set out in a grid of cells in the order glyphs/layout.json
# lists them. docs/build-glyphs.py makes them, from the typewriter's own scans and the hand-drawn character sheets.
atlas = null # glyphs/layout.json, once it's loaded

# Size of glyphs in the atlas
gw = atlasDPI / charactersPerInch
gh = atlasDPI / 8

# Shift the glyph down within its line so it sits nicely under the caret
verticalAlign = gh * .15

# How much room around a glyph to copy with it from the atlas to the canvas: across, enough that nothing gets cut off;
# up and down, enough for an accent over a capital or a tail under the line
padX = gw * 0.4
padY = gh * 2 / 3

# Typographer's punctuation that the typewriter doesn't have, mapped to the keys you'd actually strike (until the atlas has its own)
substitutions = "‘": "'", "’": "'", "“": "\"", "”": "\"", "–": "-", "—": "-", "×": "x"

# The x,y pixel position within the atlas of a character's glyph, or nulls if the atlas doesn't have it
getGlyphPosInAtlas = (c)->
  i = atlas?.index.get c
  return [null, null] unless i?
  [(i % atlas.columns) * atlas.cellWidth + atlas.glyphX, Math.floor(i / atlas.columns) * atlas.cellHeight + atlas.glyphY]

glyphCache = {}
glyph = (c)->
  glyphCache[c] ?= do ()->
    [gx, gy] = getGlyphPosInAtlas c
    [gx, gy] = getGlyphPosInAtlas substitutions[c] if not gx? and substitutions[c]?
    [gx, gy]

# These images store the glyph atlases, one per strike & ribbon colour
atlases = {}
atlasNames = ["regular", "light", "double", "regular-red", "light-red", "double-red"]

atlasFor = (style)-> atlases[style.weight + (if style.red then "-red" else "")]

loadAtlases = ()->
  loaded = 0
  done = ()-> document.body.classList.add "ready" if ++loaded is atlasNames.length + 1
  fetch("glyphs/layout.json").then((r)-> r.json()).then (layout)->
    atlas = Object.assign layout, index: new Map Array.from(layout.chars).map (c, i)-> [c, i]
    glyphCache = {}
    invalidate()
    done()
  for name in atlasNames
    do (name)->
      img = new Image()
      img.onload = ()->
        atlases[name] = img
        invalidate()
        done()
      img.src = "glyphs/#{name}.png"

# STYLE ###########################################################################################

# Every character on the page remembers how it was struck: regular, light, or double struck, on the black or red half
# of the ribbon, underlined, struck through, or X'd out — and whether its paragraph is centred or flush right, or a heading.
# Each character's style is packed into one character code, so a document's styles are a string alongside its text.
weights = ["regular", "light", "double"]
flags = ["red", "center", "underline", "strike", "xout", "right", "table", "header"]
encodeStyle = (style)->
  v = Math.max 0, weights.indexOf style.weight
  v |= 4 << k for flag, k in flags when style[flag]
  v |= (style.heading or 0) << 10 # 0 for body text, or the heading's level, 1 to 6
  String.fromCharCode 48 + v
decodeStyle = (code)->
  v = code.charCodeAt(0) - 48
  style = weight: weights[v & 3] ? "regular"
  style[flag] = (v & (4 << k)) isnt 0 for flag, k in flags
  style.heading = (v >> 10) & 7
  style
styleAlign = (code)->
  style = decodeStyle code
  if style.center then "center" else if style.right then "right" else "left"
alignStyle = (align)-> center: align is "center", right: align is "right"

# A paragraph runs up to & including its carriage return (or form feed)
breaks = ["\n", "\f"]
paragraphStart = (text, i)->
  i-- while i > 0 and text[i - 1] not in breaks
  i
paragraphEnd = (text, i)->
  i++ while i < text.length and text[i] not in breaks
  Math.min i + 1, text.length

# A paragraph's alignment is carried by its first character, or its carriage return if it's empty.
# The styles string has one extra entry past the end of the text, which carries the alignment of an empty last line.
alignAt = (text, codes, i)-> styleAlign codes[paragraphStart text, i] ? encodeStyle {}

# MARKDOWN ########################################################################################

# The text behind the page is Markdown. Its markers are invisible on the page and take up no room on the grid:
#   **double struck**   `light`   _underlined_ (or *underlined*)   ==red ribbon==
#   ~~struck through~~   ~~~X'd out~~~   and a whole line wrapped in -> and <- is centred, or in -> and -> flush right
#   # A heading (any level) is double struck & underlined, the way a typist would set one off
# A backslash makes the next marker character print as itself.

delimiters = # marker character → length of the run → what it does
  "*": {1: "underline", 2: "double"}
  "_": {1: "underline", 2: "double"}
  "`": {1: "light"}
  "=": {2: "red"}
  "~": {2: "strike", 3: "xout"}
escapable = "*_`=~\\-<#|"
wordChar = /[\p{L}\p{N}]/u
blankChar = /\s/

# Read one line (without its line break). kinds says what each raw character is: "text" (printed), "open" or
# "close" (an inline marker), "blockOpen" or "blockClose" (the centring arrows), or "escape" (a backslash).
parseLine = (line)->
  n = line.length
  kinds = new Array(n).fill "text"
  start = 0
  end = n
  align =
    if n >= 4 and line.startsWith("->") and line.endsWith("<-") then "center"
    else if n >= 4 and line.startsWith("->") and line.endsWith("->") then "right"
    else "left"
  if align isnt "left"
    kinds[0] = kinds[1] = "blockOpen"
    kinds[n - 2] = kinds[n - 1] = "blockClose"
    start = 2
    end = n - 2

  heading = 0
  if m = line.slice(start, end).match /^(#{1,6}) /
    heading = m[1].length
    kinds[x] = "blockOpen" for x in [start...start + heading + 1]
    start += heading + 1

  spans = parseInline line, start, end, kinds
  styles = new Array n
  base = if heading then {weight: "double", underline: true, heading} else {weight: "regular"}
  styles[x] = Object.assign {}, base, alignStyle align for x in [0...n] when kinds[x] is "text"
  applySpans styles, spans, kinds
  {kinds, styles, align, heading}

# Find the inline spans between start and end, marking their markers (and any escapes) in kinds
parseInline = (line, start, end, kinds)->
  # Find the runs of marker characters that could open or close a span
  tokens = []
  i = start
  while i < end
    c = line[i]
    if kinds[i] isnt "text"
      i++
    else if c is "\\" and i + 1 < end and line[i + 1] in escapable
      kinds[i] = "escape"
      i += 2
    else if delimiters[c]?
      j = i
      j++ while j < end and line[j] is c
      if type = delimiters[c][j - i]
        before = if i > start then line[i - 1] else " "
        after = if j < end then line[j] else " "
        canOpen = not blankChar.test after
        canClose = not blankChar.test before
        if c is "_" # Underscores inside a word stay underscores, like snake_case
          canOpen and= not wordChar.test before
          canClose and= not wordChar.test after
        tokens.push {at: i, len: j - i, key: c + (j - i), type, canOpen, canClose}
      i = j
    else
      i++

  # Pair them up, innermost first, like Markdown does
  spans = []
  stack = []
  for t in tokens
    k = -1
    if t.canClose
      k = stack.length - 1
      k-- while k >= 0 and stack[k].key isnt t.key
    if k >= 0
      o = stack[k]
      stack.length = k
      spans.push {from: o.at + o.len, to: t.at, type: t.type}
      kinds[x] = "open" for x in [o.at...o.at + o.len]
      kinds[x] = "close" for x in [t.at...t.at + t.len]
    else if t.canOpen
      stack.push t
  spans

# Each printed character takes on the style of every span it's in — the innermost wins for the strike
applySpans = (styles, spans, kinds)->
  spans.sort (a, b)-> (b.to - b.from) - (a.to - a.from)
  for span in spans
    for x in [span.from...span.to] when kinds[x] in ["text", "br"]
      if span.type in weights then styles[x].weight = span.type else styles[x][span.type] = true
  styles

# TABLES ##########################################################################################

# A table is a row of cells between pipes, then a delimiter row of dashes (colons set each column's alignment),
# then more rows:   | _Dutch oven:_ | ==or== | _Slow cooker:_ |
#                   |---|:---:|---|
#                   | simmer on low<br>stir occasionally | | transfer to slow cooker |
# On the page, each cell boundary is a printed (but invisible) character, like a tab, and so is each <br>.
cellBreak = "\u001F"
cellLineBreak = " "

isRowLine = (line)-> /^\s*\|/.test line

# Where a row's cells are: the unescaped pipes between the leading & trailing ones
splitRow = (line)->
  i = 0
  i++ while i < line.length and line[i] in [" ", "\t"]
  first = i + 1 # just past the leading pipe
  e = line.length
  e-- while e > first and line[e - 1] in [" ", "\t"]
  last = if e > first and line[e - 1] is "|" and line[e - 2] isnt "\\" then e - 1 else e
  cells = []
  s = first
  x = first
  while x < last
    if line[x] is "\\"
      x += 2
      continue
    if line[x] is "|"
      cells.push [s, x]
      s = x + 1
    x++
  cells.push [s, last]
  {first, last, cells}

# The alignment of each column, if this line is a table's delimiter row
delimiterAligns = (line)->
  return null unless /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/.test(line) and line.includes "|"
  for [s, e] in splitRow(if isRowLine line then line else "|" + line).cells
    cell = line.slice(s, e).trim()
    if cell.startsWith(":") and cell.endsWith(":") then "center" else if cell.endsWith(":") then "right" else "left"

parseRow = (line, aligns, header)->
  n = line.length
  kinds = new Array(n).fill "text"
  styles = new Array n
  {first, last, cells} = splitRow line
  kinds[x] = "blockOpen" for x in [0...first]
  kinds[x] = "blockClose" for x in [last...n]
  termStyle = null
  for [cs, ce], c in cells
    base = Object.assign {weight: "regular", table: true, header}, alignStyle aligns[c] ? "left"
    # One space each side of a pipe is padding; any more is part of the cell, so a space typed at the end of a cell
    # stays put until the next word arrives
    a = cs
    a++ if a < ce and line[a] is " "
    z = ce
    z-- if z > a and line[z - 1] is " "
    kinds[x] = "blockOpen" for x in [cs...a]
    kinds[x] = "blockClose" for x in [z...ce]
    # A <br> breaks the line inside the cell
    x = a
    while x < z
      if m = line.slice(x, z).match /^<br\s*\/?>/i
        kinds[x] = "br"
        kinds[y] = "brTail" for y in [x + 1...x + m[0].length]
        x += m[0].length
      else
        x++
    spans = parseInline line, a, z, kinds
    styles[x] = Object.assign {}, base for x in [a...z] when kinds[x] in ["text", "br"]
    applySpans styles, spans, kinds
    # The pipe after each cell (or the end of the row) carries that cell's column alignment
    if ce < last
      kinds[ce] = "sep"
      styles[ce] = Object.assign {}, base
    termStyle = base
  {kinds, styles, termStyle}

# Read just a cell's contents, to check it reads back the way it was written
parseCell = (md)->
  kinds = new Array(md.length).fill "text"
  x = 0
  while x < md.length
    if m = md.slice(x).match /^<br\s*\/?>/i
      kinds[x] = "br"
      kinds[y] = "brTail" for y in [x + 1...x + m[0].length]
      x += m[0].length
    else
      x++
  spans = parseInline md, 0, md.length, kinds
  styles = (Object.assign {weight: "regular"} for x in [0...md.length])
  applySpans styles, spans, kinds
  {kinds, styles}

# Read a whole document: the printed text, a style for each printed character (plus one for the end),
# where each printed character sits in the Markdown, and what every Markdown character is
parseMarkdown = (raw)->
  # Split it into lines first, so tables (which run across lines) can be spotted
  lines = []
  s = 0
  loop
    b = s
    b++ while b < raw.length and raw[b] not in breaks
    lines.push {start: s, end: b, text: raw.slice s, b}
    break if b is raw.length
    s = b + 1
  k = 0
  while k < lines.length
    if isRowLine(lines[k].text) and k + 1 < lines.length and (aligns = delimiterAligns lines[k + 1].text)? and
        splitRow(lines[k].text).cells.length is aligns.length
      lines[k].row = {aligns, header: true}
      lines[k + 1].delimiter = true
      k += 2
      while k < lines.length and isRowLine lines[k].text
        lines[k].row = {aligns, header: false}
        k++
    else
      k++

  chars = []
  codes = []
  rawOf = []
  kinds = []
  visBefore = new Array raw.length + 1
  termStyle = {}
  headerTerm = {}
  for line, k in lines
    if line.delimiter
      # The delimiter row doesn't print. Its line break is the one that ends the header row on the page.
      for x in [line.start...line.end]
        visBefore[x] = chars.length
        kinds.push "delimiter"
      termStyle = headerTerm
    else
      parsed = if line.row then parseRow(line.text, line.row.aligns, line.row.header) else parseLine(line.text)
      for kind, x in parsed.kinds
        visBefore[line.start + x] = chars.length
        kinds.push kind
        printed = switch kind
          when "text" then line.text[x]
          when "sep" then cellBreak
          when "br" then cellLineBreak
        if printed?
          chars.push printed
          codes.push encodeStyle parsed.styles[x]
          rawOf.push line.start + x
      termStyle =
        if line.row then Object.assign {}, parsed.termStyle
        else Object.assign alignStyle(parsed.align), heading: parsed.heading
    break if line.end is raw.length
    visBefore[line.end] = chars.length
    if line.row?.header
      # The header row's own line break is hidden; the delimiter row's ends it on the page
      kinds.push "delimiter"
      headerTerm = termStyle
    else
      kinds.push "text"
      chars.push raw[line.end]
      codes.push encodeStyle termStyle
      rawOf.push line.end
  visBefore[raw.length] = chars.length
  rawOf.push raw.length
  codes.push encodeStyle termStyle # The end carries the last line's alignment (or heading, or table cell)
  {raw, text: chars.join(""), styles: codes.join(""), rawOf, kinds, visBefore}

# Spans open outermost-first in this order, so light text with an underline reads `_like this_`
spanOrder = ["light", "double", "underline", "red", "strike", "xout"]
hasSpan = (style, type)-> if type in weights then style.weight is type else style[type]

markerFor = (type, opts)-> switch type
  when "light" then "`"
  when "double" then "**"
  when "underline" then opts.underline
  when "red" then "=="
  when "strike" then "~~"
  when "xout" then "~~~"

# Markdown can't start or end a span on a space, so spans shrink to fit the words inside them
trimSpans = (chars, styles)->
  for type in spanOrder
    i = 0
    while i < chars.length
      unless hasSpan styles[i], type
        i++
        continue
      j = i
      j++ while j < chars.length and hasSpan styles[j], type
      a = i
      a++ while a < j and blankChar.test chars[a]
      z = j
      z-- while z > a and blankChar.test chars[z - 1]
      for x in [i...a].concat [z...j]
        if type in weights then styles[x].weight = "regular" else styles[x][type] = false
      i = j
  styles

writeLine = (chars, styles, align, heading, opts)->
  # Where each run of each kind of span ends, so the one that runs longest can go on the outside
  runEnd = {}
  for type in spanOrder
    ends = new Array chars.length
    for i in [chars.length - 1..0] by -1 when chars.length
      ends[i] = if i + 1 < chars.length and hasSpan(styles[i + 1], type) then ends[i + 1] else i + 1
    runEnd[type] = ends

  out = ""
  stack = []
  for c, i in chars
    want = (type for type in spanOrder when hasSpan styles[i], type)
    want = [] if opts.split and blankChar.test c # Last resort: no span crosses a space
    # Close any span that's ending (and whatever's nested inside it), then open the ones that are starting,
    # longest first, so a short span inside a long one never forces the long one to close and reopen
    k = stack.findIndex (type)-> type not in want
    if k >= 0
      out += markerFor type, opts for type in stack.slice(k).reverse()
      stack.length = k
    opening = (type for type in want when type not in stack)
    opening.sort (x, y)-> (runEnd[y][i] - runEnd[x][i]) or (spanOrder.indexOf(x) - spanOrder.indexOf(y))
    for type in opening
      out += markerFor type, opts
      stack.push type
    out +=
      if c is cellLineBreak then (if opts.cell then "<br>" else " ")
      else if c is cellBreak then " " # A cell boundary that's ended up outside a table is just a space
      else if c is "|" and opts.cell then "\\|"
      else if opts.escape and c in escapable then "\\" + c
      else c
  out += markerFor type, opts for type in stack.slice().reverse()
  return out if opts.cell
  if heading
    out = "#".repeat(heading) + " " + out
  else if /^#{1,6} /.test out
    out = "\\" + out # Don't let it read as a heading
  if align is "center"
    "->#{out}<-"
  else if align is "right"
    "->#{out}->"
  else if out.length >= 4 and out.startsWith("->") and (out.endsWith("<-") or out.endsWith("->"))
    "\\" + out # Don't let it read as centred or flush right
  else
    out

# Write one line of styled characters as Markdown, and check it reads back the same.
# If it doesn't (say, a stray asterisk that would pair up), try escaping the marker characters.
serializeLine = (chars, codes, align, heading)->
  styles = trimSpans chars, (decodeStyle c for c in codes)
  # A heading is double struck & underlined by being a heading, so those don't need spans of their own
  if heading
    for s in styles
      s.weight = "regular" if s.weight is "double"
      s.underline = false
  want = for s in styles
    s = Object.assign {}, s, alignStyle(align), {heading}
    Object.assign s, {weight: (if s.weight is "regular" then "double" else s.weight), underline: true} if heading
    encodeStyle s
  want = want.join ""
  attempts = [{underline: "_"}, {underline: "*"}, {underline: "_", escape: true}, {underline: "*", escape: true}]
  for opts in attempts
    md = writeLine chars, styles, align, heading, opts
    back = parseLine md
    printed = (md[x] for kind, x in back.kinds when kind is "text").join ""
    codesBack = (encodeStyle back.styles[x] for kind, x in back.kinds when kind is "text").join ""
    return md if printed is chars.join("") and codesBack is want and back.align is align and back.heading is heading
  # Nothing reads back exactly (styles that overlap in a way Markdown can't nest): keep the words and as much of the
  # styling as Markdown allows, rather than let markers show up on the page
  writeLine chars, styles, align, heading, {underline: "_", escape: true, split: true}

# Write one cell's contents, checking it reads back the same, like serializeLine
inlineKey = (s)-> encodeStyle weight: s.weight, red: s.red, underline: s.underline, strike: s.strike, xout: s.xout
serializeCell = (chars, codes)->
  styles = trimSpans chars, (decodeStyle c for c in codes)
  want = (inlineKey s for s in styles).join ""
  for opts in [{underline: "_", cell: true}, {underline: "*", cell: true}, {underline: "_", escape: true, cell: true}]
    md = writeLine chars, styles, "left", 0, opts
    back = parseCell md
    printed = (for kind, x in back.kinds when kind in ["text", "br"] then (if kind is "br" then cellLineBreak else md[x])).join ""
    codesBack = (inlineKey back.styles[x] for kind, x in back.kinds when kind in ["text", "br"]).join ""
    return md if printed is chars.join("") and codesBack is want
  writeLine chars, styles, "left", 0, {underline: "_", escape: true, cell: true, split: true}

alignMarker = (align)-> switch align
  when "center" then ":---:"
  when "right" then "---:"
  else "---"

# Write a table row. Each cell boundary (and the row's line break, or end) carries its cell's column alignment, which
# the header row writes out as the delimiter row beneath it.
serializeRow = (chars, codes, termCode)->
  cells = [[[], []]]
  aligns = []
  for c, x in chars
    if c is cellBreak
      aligns.push styleAlign codes[x]
      cells.push [[], []]
    else
      cells[cells.length - 1][0].push c
      cells[cells.length - 1][1].push codes[x]
  aligns.push if termCode? then styleAlign termCode else "left"
  md = "| " + (serializeCell cell, cellCodes for [cell, cellCodes] in cells).join(" | ") + " |"
  if decodeStyle(codes[0] ? termCode ? encodeStyle {}).header
    md += "\n| " + (alignMarker align for align in aligns).join(" | ") + " |"
  md

# Write a run of whole paragraphs back into Markdown. codes has a style for each character — plus one more when the
# run reaches the end of the document, for its last line.
serializeBlock = (text, codes)->
  out = ""
  i = 0
  loop
    j = i
    j++ while j < text.length and text[j] not in breaks
    first = decodeStyle codes[i] ? encodeStyle {}
    if first.table
      out += serializeRow Array.from(text.slice i, j), codes.slice(i, j), codes[j]
    else
      out += serializeLine Array.from(text.slice i, j), codes.slice(i, j), styleAlign(codes[i]), first.heading
    break if j is text.length
    out += text[j]
    i = j + 1
    # A block that ends on a line break stops there — unless it's the end of the document, whose last line can be empty
    break if i is text.length and not codes[i]?
  out

# LAYOUT ##########################################################################################

# Works out where every character lands: [page, line, col] for each index in the text,
# plus one extra entry for the end of the text (where the carriage sits after the last character).
# Words wrap at the right margin, tabs jump to the next stop, \n is a carriage return, and \f feeds a new sheet.
layout = null

doLayout = (g)->
  text = doc.text
  styles = doc.styles
  n = text.length
  pos = new Array n + 1
  # Each run of text that sits on one line: an ordinary line, or one line of a table cell. A table row puts several
  # of these side by side. {page, line, start, end, align, left, right} — the range of indices whose caret position
  # is in the run, how it's aligned, and the columns it's laid out between.
  lines = []
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

  addRun = (run)->
    pages.push {start: run.start, firstLine: lines.length} if run.page isnt lines[lines.length - 1]?.page
    lines.push run

  place = (i)->
    pos[i] = [page, line, col]
    last = lines[lines.length - 1]
    if last?.page is page and last.line is line and not last.cell
      last.end = i
    else
      addRun {page, line, start: i, end: i, align: alignAt(text, styles, i), left: g.left, right: g.right}

  isTableRow = (i)-> decodeStyle(styles[i] ? encodeStyle {}).table

  # Lay out a table — its rows, starting at i — and return the index just past it
  layoutTable = (i)->
    # Gather the rows, each split into cells at the (invisible) cell boundaries
    rows = []
    loop
      end = i
      end++ while end < n and text[end] not in breaks
      cells = []
      s = i
      for x in [i..end]
        if x is end or text[x] is cellBreak
          cells.push {start: s, end: x}
          s = x + 1
      rows.push {start: i, end, cells}
      i = end + 1
      break unless end < n and i < n and isTableRow(i) and not decodeStyle(styles[i]).header

    columns = Math.max (row.cells.length for row in rows)...
    header = rows[0]
    aligns = for c in [0...columns]
      at = header.cells[c]?.end
      if at? then styleAlign styles[at] ? encodeStyle {} else "left"

    # Each column is as wide as its longest line, and whatever room is left goes between the columns, so the table
    # spans the margins. If it doesn't fit, the columns share the room and their text wraps.
    natural = (0 for c in [0...columns])
    for row in rows
      for cell, c in row.cells
        for piece in text.slice(cell.start, cell.end).split cellLineBreak
          natural[c] = Math.max natural[c], piece.length
    natural = (Math.max 1, w for w in natural)
    room = g.right - g.left
    gap = 2
    if columns is 1
      widths = [room]
      gaps = []
    else if natural.reduce(((a, b)-> a + b), 0) + gap * (columns - 1) <= room
      widths = natural
      extra = room - widths.reduce(((a, b)-> a + b), 0) - gap * (columns - 1)
      gaps = (gap + Math.floor(extra / (columns - 1)) + (if c < extra % (columns - 1) then 1 else 0) for c in [0...columns - 1])
    else
      share = room - gap * (columns - 1)
      total = natural.reduce ((a, b)-> a + b), 0
      widths = (Math.max 3, Math.floor w * share / total for w in natural)
      gaps = (gap for c in [0...columns - 1])
    xs = [g.left]
    xs.push xs[c] + widths[c] + gaps[c] for c in [0...columns - 1]

    for row in rows
      # Wrap each cell's text within its column
      laid = for cell, c in row.cells
        width = widths[c]
        cellLines = [[]]
        at = 0
        k = cell.start
        breakLine = ()->
          cellLines.push []
          at = 0
        while k < cell.end
          ch = text[k]
          if ch is cellLineBreak
            cellLines[cellLines.length - 1].push [k++, at]
            breakLine()
          else if ch in [" ", "\t"]
            breakLine() if at > width
            cellLines[cellLines.length - 1].push [k++, at++]
          else
            j = k
            j++ while j < cell.end and text[j] not in [" ", "\t", cellLineBreak]
            breakLine() if at + (j - k) > width and at > 0
            while k < j
              breakLine() if at >= width
              cellLines[cellLines.length - 1].push [k++, at++]
        # The cell's boundary (or the row's line break) is where the caret sits at the end of the cell
        cellLines[cellLines.length - 1].push [cell.end, at]
        cellLines

      height = Math.max (cellLines.length for cellLines in laid)...
      newpage() if line + height > g.linesPerPage and line > 0
      for cellLines, c in laid
        for entries, m in cellLines when entries.length
          for [k, at] in entries
            pos[k] = [page, line + m, xs[c] + at]
          addRun {page, line: line + m, start: entries[0][0], end: entries[entries.length - 1][0], cell: true,
            align: aligns[c], left: xs[c], right: xs[c] + widths[c]}
      line += height
      if text[row.end] is "\f"
        newpage()
      else if line >= g.linesPerPage
        line = 0
        page++
      col = g.left
    i

  i = 0
  while i < n
    if (i is 0 or text[i - 1] in breaks) and isTableRow i
      i = layoutTable i
      continue
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
  place n unless pos[n]? # (A table at the very end has already placed it, at the end of its last cell)

  # Centred lines are spaced in from the left margin by half the room left over, and flush right lines by all of it,
  # landing on the grid the same way a typist would backspace from the middle or from the right margin.
  # Table cells do the same within their columns.
  blank = [" ", "\n", "\t", "\f", cellBreak, cellLineBreak]
  for ln in lines when ln.align isnt "left"
    last = null
    last = i for i in [ln.start..ln.end] when i < n and text[i] not in blank
    width = if last? then pos[last][2] + 1 - ln.left else 0
    room = Math.max 0, ln.right - ln.left - width
    shift = if ln.align is "center" then Math.floor room / 2 else room
    pos[i][2] += shift for i in [ln.start..ln.end]

  for p, k in pages
    p.end = pages[k + 1]?.start ? n + 1
    p.lastLine = (pages[k + 1]?.firstLine ? lines.length) - 1

  # The rows of type, top to bottom, and the runs on each — for moving up & down
  rowKeys = []
  rowRuns = new Map()
  for ln in lines
    key = rowKey ln
    rowKeys.push key unless rowRuns.has key
    (rowRuns.get(key) ? rowRuns.set(key, []).get(key)).push ln
  rowKeys.sort (a, b)-> a - b

  layout = {text, n, pos, lines, pages, rowKeys, rowRuns}

rowKey = (ln)-> ln.page * 100000 + ln.line

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

# Of a row's runs (several, across a table), the one nearest a column
runNearest = (runs, col)->
  best = null
  bestDistance = Infinity
  for ln in runs
    distance = if col < ln.left then ln.left - col else if col > ln.right then col - ln.right else 0
    [best, bestDistance] = [ln, distance] if distance < bestDistance
  best

# The index nearest to a spot on a page, in inches from the sheet's top left corner
indexAtPoint = (g, page, x, y)->
  return layout.n if page >= layout.pages.length
  return 0 if page < 0
  p = layout.pages[page]
  line = Math.floor (y * linesPerInch - g.top) / g.spacing
  col = Math.round x * charactersPerInch
  # The nearest row of type on this page, then the run on it nearest the pointer
  nearest = null
  for k in [p.firstLine..p.lastLine]
    ln = layout.lines[k]
    nearest = ln.line if not nearest? or Math.abs(ln.line - line) < Math.abs(nearest - line)
  runs = (layout.lines[k] for k in [p.firstLine..p.lastLine] when layout.lines[k].line is nearest)
  indexAtCol runNearest(runs, col), col

# RENDERING #######################################################################################

$ = (q)-> document.querySelector q

pagesElm = $ ".pages"
selectionElm = $ ".selection"
caretElm = $ ".caret"
input = $ ".input"
deckElm = $ ".ui"
formatMenu = $ ".format"

# A page's link (/s/<id>) has the page built into it, as the server has it
shared = window.sharedPage
viewing = false # reading the page, rather than typing on it

pageViews = []
renderVersion = 0
geo = null

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
  edge = document.createElement "div"
  edge.className = "edge"
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
  elm.append canvas, guide, edge, strip, top, bottom, spacing
  pagesElm.insertBefore elm, selectionElm
  {elm, canvas, guide, strip, top, bottom, spacing, ctx: canvas.getContext("2d"), key: null}

# Three little engraved lines, spaced apart by gap — flush left, centred, or flush right
linesIcon = (gap, align)->
  widths = if align in ["center", "right"] then [10, 6, 10] else [10, 10, 10]
  lines = for w, k in widths
    x1 = switch align
      when "center" then 10 - w / 2
      when "right" then 15 - w
      else 5
    y = 10 + (k - 1) * gap
    "<line x1='#{x1}' x2='#{x1 + w}' y1='#{y}' y2='#{y}'/>"
  "<svg viewBox='0 0 20 20'>#{lines.join ""}</svg>"

# A lever that clicks into one of a few positions, like the line space lever on an Olympia SM9
makeLever = (name, values, icon, choose)->
  lever = document.createElement "div"
  lever.className = "lever #{name}"
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

    view.top.style.top = g.top / linesPerInch * pxPerInch + "px"
    setFlag view.top, g.top, settings.linkTopBottom
    view.top.title = "Top margin: #{g.top} lines (#{fmt g.top / linesPerInch} in)"
    view.bottom.style.top = (g.h - g.bottom / linesPerInch) * pxPerInch + "px"
    setFlag view.bottom, g.bottom, settings.linkTopBottom
    view.bottom.title = "Bottom margin: #{g.bottom} lines (#{fmt g.bottom / linesPerInch} in) · #{g.linesPerPage} lines per page"
    view.spacing.style.top = g.top / linesPerInch * pxPerInch + view.top.offsetHeight / 2 + 6 + "px"
    setLever view.spacing, spacings, settings.spacing
    renderStrip view, g

    # Only redraw pages whose contents actually changed
    {start, end} = layout.pages[p]
    key = "#{renderVersion}|#{pw}|#{layout.text.slice start, end}|#{doc.styles.slice start, end}"
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
  strike = (img, c, px, py)->
    [gx, gy] = glyph c
    return unless gx? # A key the machine doesn't have strikes nothing, leaving a blank space
    ctx.drawImage img, gx - padX, gy - padY, gw + padX*2, gh + padY*2, px - padX, py - padY, gw + padX*2, gh + padY*2

  # Where a line wraps in the middle of an underlined (or struck through, or X'd out) phrase, the typist stops at the
  # last letter on the line and starts again at the first one on the next: the spaces around the wrap go bare
  bare = new Set
  blank = (k)-> text[k] in [" ", "\n", "\f", cellBreak, cellLineBreak]
  for ln in layout.lines when ln.page is p
    a = ln.start
    a++ while a <= ln.end and blank a
    z = ln.end
    z-- while z >= a and blank z
    bare.add k for k in [ln.start...a]
    bare.add k for k in [z + 1..ln.end] by 1 when z < ln.end

  for i in [start...Math.min end, layout.n]
    c = text[i]
    continue if c in ["\n", "\t", "\f", cellBreak, cellLineBreak]
    style = decodeStyle doc.styles[i]
    img = atlasFor style
    continue unless img?
    [_, line, col] = layout.pos[i]
    px = col * gw
    py = lineTop(geo, line) * atlasDPI + verticalAlign
    strike img, c, px, py unless c is " "
    continue if bare.has i
    # Underlining, striking through, and X-ing out are done the typist's way:
    # another key struck over the same spot, ink on ink
    strike img, "_", px, py if style.underline
    strike img, "-", px, py if style.strike
    strike img, "X", px, py if style.xout
  null

# Along the top of each sheet: the left & right margin tabs, the tab stops, and the centre mark
renderStrip = (view, g)->
  step = pxPerInch / charactersPerInch
  marks = [
    {kind: "center", col: g.w * charactersPerInch / 2, title: "Centre of the sheet"}
    {kind: "left", col: g.left, value: g.left, title: "Left margin: #{g.left} characters (#{fmt g.left / charactersPerInch} in) in from the left edge"}
    {kind: "right", col: g.right, value: g.cols - g.right, title: "Right margin: #{g.cols - g.right} characters (#{fmt (g.cols - g.right) / charactersPerInch} in) in from the right edge · #{g.right - g.left} characters per line"}
  ]
  for col, index in settings.tabs
    marks.push {kind: "tab", col, index, title: "Tab stop at #{col} — drag it away to clear it"}

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
      else "center-mark"
    e.classList.toggle "removing", drag?.kind is "tab" and drag.index is mark.index and drag.removing
    e.classList.toggle "dragging", drag?.kind is mark.kind and (mark.kind isnt "tab" or drag.index is mark.index)
    e.dataset.kind = mark.kind
    e.dataset.index = mark.index ? ""
    e.style.left = mark.col * step + "px"
    if mark.value? then setFlag e, mark.value, settings.linkLeftRight else e.textContent = ""
    e.title = mark.title ? ""
  null

# Each margin tab shows how far in it sits from its own edge, under a link that couples it to the opposite margin
linkIcon = "<svg viewBox='0 0 16 16'><path d='M6.5 9.5l3-3'/><path d='M7 4.5l1-1a2.5 2.5 0 0 1 3.5 3.5l-1 1'/><path d='M9 11.5l-1 1a2.5 2.5 0 0 1-3.5-3.5l1-1'/></svg>"
brokenLinkIcon = "<svg viewBox='0 0 16 16'><path d='M7 4.5l1-1a2.5 2.5 0 0 1 3.5 3.5l-1 1'/><path d='M9 11.5l-1 1a2.5 2.5 0 0 1-3.5-3.5l1-1'/><path d='M2.5 5.5l-1-.3M5.5 2.5l-.3-1M13.5 10.5l1 .3M10.5 13.5l.3 1'/></svg>"

setFlag = (elm, value, linked)->
  html = "<span class='link#{if linked then " linked" else ""}' title='#{if linked then "Linked to the opposite margin — click to unlink" else "Click to link to the opposite margin"}'>#{if linked then linkIcon else brokenLinkIcon}</span><span class='value'>#{value}</span>"
  elm.innerHTML = html unless elm.dataset.html is html
  elm.dataset.html = html

# Caret position for index i, in CSS px relative to the .pages container
caretPoint = (i)->
  [page, line, col] = layout.pos[i]
  view = pageViews[page]
  x: view.elm.offsetLeft + col / charactersPerInch * pxPerInch
  y: view.elm.offsetTop + lineTop(geo, line) * pxPerInch
  h: pxPerInch / linesPerInch

focusIndex = ()->
  Math.min visAt(if input.selectionDirection is "backward" then input.selectionStart else input.selectionEnd), layout.n

# Keep a lone caret out of the middle of a marker, so whatever's typed lands where it looks like it will
normalizeCaret = ()->
  r = input.selectionStart
  return unless r is input.selectionEnd
  return if doc.kinds[r - 1] is "delimiter" # Typing a table's delimiter row: leave the caret where the typing is
  # Likewise typing a row by hand, past the padding or pipe just typed at the end of it
  return if doc.kinds[r - 1] is "blockClose" and (r is doc.raw.length or doc.raw[r] in breaks) and inTable visAt r
  c = rawAt visAt r
  input.setSelectionRange c, c unless c is r

renderSelection = ()->
  return unless layout? and pageViews.length
  normalizeCaret() unless applying or composing
  [a, b] = selected()

  # Caret goes on the moving end of the selection
  focus = focusIndex()
  c = caretPoint focus
  Object.assign caretElm.style, left: c.x - 1 + "px", top: c.y + "px", height: c.h + "px"
  Object.assign input.style, left: c.x + "px", top: c.y + "px", height: c.h + "px" unless composing

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
  return if viewing
  r = caretElm.getBoundingClientRect()
  limit = deckElm.getBoundingClientRect().top - 32
  if r.bottom > limit
    window.scrollBy 0, r.bottom - limit
  else if r.top < 48
    window.scrollBy 0, r.top - 48

# EDITING #########################################################################################

# The hidden textarea holds the Markdown, the selection, and the undo history. Everything else works in terms of the
# printed text — what's actually on the page — and maps back to the Markdown underneath.
doc = parseMarkdown ""
reparse = ()-> doc = parseMarkdown input.value

# Where the caret sits in the Markdown when it's before printed character k. At the edge of a span, the caret stays
# outside it — so typing after an underlined word isn't underlined, the way it would be on the machine — but inside
# the centring arrows, and never between a backslash and the character it escapes.
rawAtIn = (d, k)->
  r = d.rawOf[clamp k, 0, d.text.length]
  r++ while r < d.kinds.length and d.kinds[r] in ["close", "blockOpen"]
  r-- while r > 0 and d.kinds[r - 1] in ["open", "blockClose", "escape", "delimiter"]
  r
rawAt = (k)-> rawAtIn doc, k
visAt = (r)-> doc.visBefore[clamp r, 0, doc.raw.length]

# The selection, in printed characters
selected = ()-> [visAt(input.selectionStart), visAt(input.selectionEnd)]

applying = false

# Swap a stretch of the Markdown for something else, through the browser so it lands in the undo history
replaceRaw = (start, end, str)->
  return if viewing or input.value.slice(start, end) is str
  applying = true
  input.focus preventScroll: true
  input.setSelectionRange start, end
  done = if str.length then document.execCommand "insertText", false, str else document.execCommand "delete"
  unless done
    input.setRangeText str, start, end, "end"
    input.dispatchEvent new Event "input"
  applying = false

# Replace printed characters [a, b) with ins (styled insCodes), then rewrite every paragraph it touched as Markdown,
# so spans stay balanced however the text around them changes
# opts.select: the selection afterwards, in printed characters (the caret after what's inserted, otherwise)
# opts.endPatch: changes the style carried by the end of the document (its last line's alignment, or whether it's a
#   heading or a table row)
# opts.follow: whether the carriage follows the caret (yes, unless it's a restyle)
# opts.keepUntil: a table's cell boundaries & row breaks in [a, keepUntil) are kept unless their whole row is going.
#   Edits that put everything back themselves (restyling, say) pass a.
edit = (a, b, ins, insCodes, opts = {})->
  {select, endPatch, follow = true, keepUntil = b} = opts
  {text, styles} = doc
  # Deleting part of a table clears the text but keeps its cells and rows, unless whole rows go
  [keep, keepCodes] = tableStructureIn a, keepUntil
  ins += keep
  insCodes += keepCodes
  newText = text.slice(0, a) + ins + text.slice(b)
  newCodes = styles.slice(0, a) + insCodes + styles.slice(b)
  if endPatch?
    newCodes = newCodes.slice(0, -1) + encodeStyle Object.assign decodeStyle(newCodes.slice -1), endPatch
  start = paragraphStart text, a
  end = paragraphEnd text, b
  newEnd = end + ins.length - (b - a)
  rawStart = if start is 0 then 0 else doc.rawOf[start - 1] + 1
  rawEnd = if end is text.length then doc.raw.length else doc.rawOf[end - 1] + 1
  codes = newCodes.slice start, newEnd + (if end is text.length then 1 else 0)
  replaceRaw rawStart, rawEnd, serializeBlock newText.slice(start, newEnd), codes
  [anchor, focus] = select ? [a + ins.length - keep.length, a + ins.length - keep.length]
  setSelection anchor, focus, follow

# Type over the selection (or into an empty centred or flush right line), keeping the style of what's being replaced
# Is printed position k in a table row? (A row's style is carried by its first character, like a paragraph's.)
inTable = (k)-> decodeStyle(doc.styles[paragraphStart doc.text, k] ? encodeStyle {}).table

# The cell boundaries and row breaks in [a, b) that have to stay, because the cell or row they belong to doesn't go
# entirely, as [characters, styles]
tableStructureIn = (a, b)->
  {text, styles} = doc
  keep = ""
  keepCodes = ""
  for x in [a...b]
    isBoundary = text[x] is cellBreak or (text[x] in breaks and decodeStyle(styles[x]).table)
    continue unless isBoundary
    rowStart = paragraphStart text, x
    rowEnd = paragraphEnd(text, x) - 1 # the row's line break
    unless a <= rowStart and rowEnd < b
      keep += text[x]
      keepCodes += styles[x]
  [keep, keepCodes]

typeText = (str)->
  [a, b] = selected()
  {text} = doc
  style = if a < b then decodeStyle doc.styles[a] else {}
  Object.assign style, alignStyle alignAt text, doc.styles, a
  if inTable a
    # Typing in a table: the row's flags come along, and Return breaks the line inside the cell — except at the end
    # of the table's last cell, where it leaves the table
    rowStyle = decodeStyle doc.styles[paragraphStart text, a]
    Object.assign style, table: true, header: rowStyle.header
    atRowEnd = b is text.length or text[b] in breaks
    leaving = atRowEnd and (b is text.length or not inTable b + 1)
    str = str.replace /\n/g, cellLineBreak unless leaving and str is "\n"
  codes = encodeStyle(style).repeat(str.length)
  # A new line after a heading (or a table) is body text: the line break that will start it stops carrying them
  if str[str.length - 1] in breaks and (b is text.length or text[b] in breaks)
    plain = {heading: 0, table: false, header: false}
    if inTable a
      Object.assign plain, alignStyle "left"
      codes = codes.slice(0, -1) + (doc.styles[b] ? codes.slice -1) # The row keeps its line break, and its alignment
    if b < text.length
      next = encodeStyle Object.assign decodeStyle(doc.styles[b]), plain
      return edit a, b + 1, str + text[b], codes + next, select: [a + str.length, a + str.length], keepUntil: b
    else
      return edit a, b, str, codes, endPatch: plain
  edit a, b, str, codes

isBlank = (c)-> c? and blankChar.test(c) and c not in breaks

# Delete the way the key says to, a printed character (or word, or line) at a time
deleteFor = (inputType)->
  [a, b] = selected()
  return edit a, b, "", "" if a < b
  {text} = doc
  k = a
  [from, to] = switch inputType
    when "deleteContentBackward" then [k - 1, k]
    when "deleteContentForward" then [k, k + 1]
    when "deleteWordBackward"
      j = k
      j-- while j > 0 and isBlank text[j - 1]
      j-- while j > 0 and not blankChar.test text[j - 1]
      j = k - 1 if j is k
      [j, k]
    when "deleteWordForward"
      j = k
      j++ while j < text.length and isBlank text[j]
      j++ while j < text.length and not blankChar.test text[j]
      j = k + 1 if j is k
      [k, j]
    when "deleteSoftLineBackward", "deleteHardLineBackward"
      ln = layout.lines[lineIndexOf k]
      [(if ln.start < k then ln.start else k - 1), k]
    when "deleteSoftLineForward", "deleteHardLineForward"
      ln = layout.lines[lineIndexOf k]
      [k, (if ln.end > k then ln.end else k + 1)]
    else [k, k]
  from = clamp from, 0, text.length
  to = clamp to, 0, text.length
  # Don't join a paragraph onto a table, or a table onto a paragraph
  if to - from is 1 and text[from] in breaks and (inTable(from) isnt inTable(to) or (inTable(to) and not inTable(from)))
    return
  edit from, to, "", "", select: [from, from] if from < to

# Every edit that could split or join a span goes through the paragraph rewriter. Plain typing goes straight in, so
# typing Markdown by hand works too.
input.addEventListener "beforeinput", (e)->
  t = e.inputType
  # An accent typed with a dead key (Option-n, then n, for ñ), or any input method, is the browser's to finish: Safari
  # replaces the pending ˜ with the ñ by "deleting" it, which mustn't be taken for a press of the delete key
  return if applying or composing or e.isComposing or /Composition/.test t
  [a, b] = selected()
  emptyAlignedLine = a is b and alignAt(doc.text, doc.styles, a) isnt "left" and paragraphStart(doc.text, a) is a and
    doc.text[a] in [undefined, "\n", "\f"] and not input.value.slice(0, input.selectionStart).endsWith "->"
  # The first letter typed into an empty table cell rewrites the row, so it reads "| ok |" rather than "| ok|"
  r = input.selectionStart
  emptyCell = a is b and inTable(a) and input.value.slice(r - 2, r + 1) is "| |" and input.value[r - 3] isnt "\\" and
    /\S/.test e.data ? ""
  if t in ["insertText", "insertReplacementText"] and (a < b or emptyAlignedLine or emptyCell)
    e.preventDefault()
    typeText e.data ? e.dataTransfer?.getData("text/plain") ? ""
  else if t in ["insertLineBreak", "insertParagraph"]
    e.preventDefault()
    typeText "\n"
  else if t.startsWith "delete"
    e.preventDefault()
    deleteFor t

# Pasting over a selection replaces it in one step, so one undo takes it back. Plain text takes on the style of what
# it replaces, like typing over it; pasted Markdown keeps its own. (The paste event is the one that reliably carries
# the clipboard's text.)
input.addEventListener "paste", (e)->
  [a, b] = selected()
  return unless a < b
  pasted = e.clipboardData?.getData("text/plain") ? ""
  e.preventDefault()
  return typeText pasted if parseMarkdown(pasted).text.length is pasted.length
  {text, styles} = doc
  [keep, keepCodes] = tableStructureIn a, b
  start = paragraphStart text, a
  end = paragraphEnd text, b
  newEnd = end - (b - a) + keep.length
  codes = (styles.slice(0, a) + keepCodes + styles.slice(b)).slice start, newEnd + (if end is text.length then 1 else 0)
  md = serializeBlock (text.slice(0, a) + keep + text.slice(b)).slice(start, newEnd), codes
  at = rawAtIn parseMarkdown(md), a - start
  rawStart = if start is 0 then 0 else doc.rawOf[start - 1] + 1
  rawEnd = if end is text.length then doc.raw.length else doc.rawOf[end - 1] + 1
  replaceRaw rawStart, rawEnd, md.slice(0, at) + pasted + md.slice(at)
  caret = rawStart + at + pasted.length
  input.setSelectionRange caret, caret
  renderSelection()
  followCaret()

# Copy and cut write well-formed Markdown, even when the selection starts or ends inside a span
copyMarkdown = (e)->
  [a, b] = selected()
  return false unless a < b
  e.preventDefault()
  e.clipboardData.setData "text/plain", serializeBlock doc.text.slice(a, b), doc.styles.slice(a, b) + encodeStyle {}
  true
input.addEventListener "copy", copyMarkdown
input.addEventListener "cut", (e)->
  if copyMarkdown e
    [a, b] = selected()
    edit a, b, "", ""

# Restyle the selected characters
restyleWith = (changes)->
  [a, b] = selected()
  return unless a < b
  [anchor, focus] = getAnchorFocus()
  codes = (encodeStyle Object.assign decodeStyle(c), changes for c in doc.styles.slice a, b).join ""
  edit a, b, doc.text.slice(a, b), codes, select: [anchor, focus], follow: false, keepUntil: a # The carriage stays put

# Capitals are typed over the letters themselves, like shift lock. Pressing Caps again puts back the letters as they
# were, as long as this session remembers them; otherwise they go to lower case. Undo always works too.
capsMemory = new Map()
sameLength = (str, fn)-> (for c in str then (if fn(c).length is 1 then fn(c) else c)).join ""
toUpper = (str)-> sameLength str, (c)-> c.toUpperCase()
toLower = (str)-> sameLength str, (c)-> c.toLowerCase()
isCaps = (str)-> /\p{L}/u.test(str) and toUpper(str) is str

toggleCaps = ()->
  [a, b] = selected()
  return unless a < b
  [anchor, focus] = getAnchorFocus()
  seg = doc.text.slice a, b
  if isCaps seg
    replacement = capsMemory.get(seg) ? toLower seg
  else
    replacement = toUpper seg
    capsMemory.set replacement, seg
  edit a, b, replacement, doc.styles.slice(a, b), select: [anchor, focus], follow: false, keepUntil: a

# Align every paragraph the selection touches — or just the one the caret is in
setAlign = (align)->
  [a, b] = selected()
  [anchor, focus] = getAnchorFocus()
  text = doc.text
  return setColumnAlign align if inTable a
  b-- if b > a and text[b - 1] in breaks # A selection ending just after a carriage return stops at that line
  start = paragraphStart text, a
  end = paragraphEnd text, b
  codes = (encodeStyle Object.assign decodeStyle(c), alignStyle align for c in doc.styles.slice start, end).join ""
  endPatch = if end is text.length then alignStyle align else null
  edit start, end, text.slice(start, end), codes, select: [anchor, focus], endPatch: endPatch, follow: false, keepUntil: start

# Where a printed position sits in a table: its table's rows, and which column it's in
tableAt = (k)->
  {text, styles} = doc
  rowStart = paragraphStart text, k
  column = (x for x in [rowStart...k] when text[x] is cellBreak).length
  start = rowStart
  until decodeStyle(styles[start]).header or start is 0 or not inTable start - 1
    start = paragraphStart text, start - 1
  end = paragraphEnd text, k
  end = paragraphEnd text, end while end < text.length and inTable(end) and not decodeStyle(styles[end]).header
  {start, end, column}

# The end of column c's cell in the row starting at rowStart: its cell boundary, or the row's line break
cellEndIn = (rowStart, c)->
  {text} = doc
  x = rowStart
  seen = 0
  while x < text.length and text[x] not in breaks
    if text[x] is cellBreak
      return x if seen is c
      seen++
    x++
  if seen is c then x else null

columnAlignAt = (k)->
  {start, column} = tableAt k
  at = cellEndIn start, column
  styleAlign doc.styles[at] ? encodeStyle {}

# The alignment lever, in a table, sets the whole column the caret is in
setColumnAlign = (align)->
  [anchor, focus] = getAnchorFocus()
  {start, end, column} = tableAt focus
  {text, styles} = doc
  codes = styles.slice(start, end).split ""
  rowStart = start
  while rowStart < end
    at = cellEndIn rowStart, column
    if at?
      x = at
      x-- while x > rowStart and text[x - 1] isnt cellBreak
      for y in [x..at] when y - start < codes.length
        codes[y - start] = encodeStyle Object.assign decodeStyle(codes[y - start]), alignStyle align
    rowStart = paragraphEnd text, rowStart
  endPatch = if end is text.length and cellEndIn(paragraphStart(text, end), column) is end then alignStyle align else null
  edit start, end, text.slice(start, end), codes.join(""), select: [anchor, focus], endPatch: endPatch, follow: false, keepUntil: start

# Tab moves to the next cell (selecting what's in it), Shift-Tab to the one before. Tab in the last cell adds a row.
tabToCell = (back)->
  {text, styles} = doc
  k = focusIndex()
  cellStart = (x)->
    x-- while x > 0 and text[x - 1] isnt cellBreak and text[x - 1] not in breaks
    x
  cellEnd = (x)->
    x++ while x < text.length and text[x] isnt cellBreak and text[x] not in breaks
    x
  if back
    s = cellStart k
    return if s is 0 or not (text[s - 1] is cellBreak or inTable s - 1)
    setSelection cellStart(s - 1), s - 1
  else
    e = cellEnd k
    if text[e] is cellBreak or (e < text.length and inTable(e + 1) and not decodeStyle(styles[e + 1]).header)
      setSelection e + 1, cellEnd e + 1
    else
      # The table's last cell: add a row with as many cells as this one
      rowStart = paragraphStart text, k
      bounds = (x for x in [rowStart...e] when text[x] is cellBreak)
      boundCodes = (encodeStyle Object.assign decodeStyle(styles[x]), header: false for x in bounds).join ""
      row = "\n" + cellBreak.repeat bounds.length
      if e < text.length
        next = encodeStyle Object.assign decodeStyle(styles[e]), header: false
        edit e, e + 1, row + text[e], styles[e] + boundCodes + next, select: [e + 1, e + 1], keepUntil: e
      else
        edit e, e, row, styles[e] + boundCodes, select: [e + 1, e + 1], endPatch: {header: false}

# A little menu that pops up over a selection, for striking it differently
renderFormatMenu = ()->
  [a, b] = selected()
  show = a < b and not pointer? and document.activeElement is input and not viewing
  formatMenu.hidden = not show
  return unless show

  # Line breaks, cell breaks, and the spaces at the ends of lines never carry a span (Markdown has nowhere to put it),
  # so only the printed letters count when showing whether the selection is already struck that way
  inked = (i for i in [a...b] when /\S/.test(doc.text[i]) and doc.text[i] isnt cellBreak)
  inked = [a...b] unless inked.length
  sel = (decodeStyle doc.styles[i] for i in inked)
  for btn in formatMenu.querySelectorAll "[data-weight]"
    btn.classList.toggle "active", sel.every (style)-> style.weight is btn.dataset.weight
  for btn in formatMenu.querySelectorAll "[data-toggle]"
    btn.classList.toggle "active", sel.every (style)-> style[btn.dataset.toggle]
  formatMenu.querySelector("[data-caps]").classList.toggle "active", isCaps doc.text.slice a, b

  first = caretPoint a
  menuH = formatMenu.offsetHeight
  pageTop = pageViews[layout.pos[a][0]].elm.offsetTop
  top = if first.y - menuH - 10 > pageTop then first.y - menuH - 10 else caretPoint(Math.max a, b - 1).y + first.h + 10
  # Keep it on screen, wherever the carriage has slid to
  left = clamp first.x, 8 - carriageX, pagesElm.clientWidth - carriageX - formatMenu.offsetWidth - 8
  Object.assign formatMenu.style, left: left + "px", top: top + "px"

for btn in formatMenu.querySelectorAll ".row > button"
  btn.addEventListener "pointerdown", (e)-> e.preventDefault() # Keep the selection while choosing
  do (btn)-> btn.onclick = ()->
    if btn.dataset.weight?
      # Light & double struck turn back to regular when pressed again
      on_ = not btn.classList.contains "active"
      restyleWith weight: if on_ then btn.dataset.weight else "regular"
    else if btn.dataset.caps?
      toggleCaps()
    else
      # Red, underline, strike, and X-out turn on for the whole selection, or off if it's all on already.
      # A line can be struck through or X'd out, but not both.
      on_ = not btn.classList.contains "active"
      changes = "#{btn.dataset.toggle}": on_
      changes.strike = false if btn.dataset.toggle is "xout" and on_
      changes.xout = false if btn.dataset.toggle is "strike" and on_
      restyleWith changes

# SETTINGS ########################################################################################

load = (name, def)->
  try
    JSON.parse(localStorage.getItem name) ? def
  catch
    def

saveText = ()-> cachePage true unless viewing

save = (name, val)->
  try localStorage.setItem name, JSON.stringify val
  val

settings = null

changeSettings = (changes)->
  size = paperSize().join()
  Object.assign settings, changes
  normalize()
  # Feeding in a different size of paper sets margins to suit it
  Object.assign settings, paperMargins paperSize()... if paperSize().join() isnt size
  save "settings", settings # new pages start out on the same paper
  saveText()
  syncControls()
  invalidate()
  publishSoon()

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

chooser = $ ".chooser"

# Flush left, centred, or flush right, for the paragraph the caret is in
alignments = ["left", "center", "right"]
alignLever = makeLever "align", alignments, ((a)-> linesIcon 4, a), setAlign
alignLever.title = "Flush left, centred, or flush right"
alignLever.classList.add "spacer"
$("#paper").after alignLever
# and the same again on the menu over a selection
menuAlignLever = makeLever "align", alignments, ((a)-> linesIcon 4, a), setAlign
menuAlignLever.title = alignLever.title
formatMenu.querySelector(".row:last-child").append menuAlignLever

syncAlign = ()->
  k = focusIndex()
  align = if inTable k then columnAlignAt k else alignAt doc.text, doc.styles, k
  setLever lever, alignments, align for lever in [alignLever, menuAlignLever]

paperName = ()->
  if settings.paper is "custom"
    savedPaperFor(settings.customW, settings.customH)?.name ? "#{fmt settings.customW} × #{fmt settings.customH}"
  else
    papers[settings.paper].short + (if settings.landscape then " landscape" else "")

# The paper key, on the left of the machine, shows what's in it and lays out the other kinds of paper to choose from
paperKey = $ "#paper"
paperKey.onclick = ()-> openChooser()

syncControls = ()->
  paperKey.textContent = paperName()
  # Lay the desk out again once the keyboard has moved on, so tabbing out of a custom size lands on the next field
  # rather than on one that's just been swept away
  setTimeout (-> renderChooser() unless chooser.hidden), 0
  null

# Hand the keyboard back to the page after pressing a key on the machine
for elm in document.querySelectorAll ".buttons button:not(#paper):not(#import)"
  elm.addEventListener "click", ()-> input.focus preventScroll: true

# PAPER CHOOSER ###################################################################################

# Press the paper key, and every kind of paper is laid out on the desk, at true relative size.
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

# Custom sizes you've named are kept for next time. Picking one sets the page's own custom size, so the page keeps it
# even for someone who doesn't have the name.
savedPapers = load "papers", []
savedPaperFor = (w, h)-> savedPapers.find (paper)-> paper.w is w and paper.h is h

renderChooser = ()->
  for btn in chooser.querySelectorAll "[data-landscape]"
    btn.classList.toggle "active", btn.dataset.landscape is "#{settings.landscape}"
  sheets = chooser.querySelector ".sheets"
  # Whatever had the keyboard on the desk gets it back once the desk is laid out again
  focused = sheets.contains(document.activeElement) and document.activeElement.dataset.key
  sheets.innerHTML = ""
  addSheet = (w, h, name, dims, active, choose)->
    sheet = document.createElement "div"
    sheet.className = "sheet"
    sheet.classList.add "active" if active
    sheet.style.width = w * chooserScale + "px"
    sheet.style.height = h * chooserScale + "px"
    sheet.innerHTML = "<span class='name'></span><span class='dims'></span>"
    sheet.querySelector(".name").textContent = name
    sheet.querySelector(".dims").textContent = dims
    sheet.onclick = ()->
      choose()
      closeChooser()
    sheets.append sheet
    sheet

  for key, paper of papers when key isnt "custom"
    do (key)->
      [w, h] = if settings.landscape then [paper.h, paper.w] else [paper.w, paper.h]
      addSheet w, h, paper.short, paper.name.split(" — ")[1], key is settings.paper, ()-> changeSettings paper: key

  custom = settings.paper is "custom"
  for paper in savedPapers
    do (paper)->
      sheet = addSheet paper.w, paper.h, paper.name, "#{fmt paper.w} × #{fmt paper.h}",
        custom and settings.customW is paper.w and settings.customH is paper.h,
        ()-> changeSettings paper: "custom", customW: paper.w, customH: paper.h
      forget = document.createElement "button"
      forget.className = "forget"
      forget.title = "Forget this size"
      forget.textContent = "×"
      forget.onclick = (e)->
        e.stopPropagation()
        savedPapers.splice savedPapers.indexOf(paper), 1
        save "papers", savedPapers
        syncControls()
      sheet.append forget

  saved = savedPaperFor settings.customW, settings.customH
  sheet = addSheet settings.customW, settings.customH, "Custom", "inches", custom and not saved?, ()->
    changeSettings paper: "custom"
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
      field.dataset.key = dim
      field.onclick = (e)-> e.stopPropagation()
      field.onchange = ()->
        unless field.value is "" or isNaN +field.value
          changeSettings paper: "custom", "#{dim}": +field.value
      size.append field
      size.append " × " if dim is "customW"
  sheet.append size
  # Name the size to keep it on the desk
  unless saved?
    keep = document.createElement "button"
    keep.className = "keep"
    keep.dataset.key = "keep"
    keep.textContent = "Save size"
    keep.onclick = (e)->
      e.stopPropagation()
      {customW: w, customH: h} = settings
      name = prompt "Name this paper size:", "#{fmt w} × #{fmt h}"
      return unless name?.trim()
      savedPapers.push {name: name.trim(), w, h}
      save "papers", savedPapers
      changeSettings paper: "custom"
    sheet.append keep
  if focused
    again = sheets.querySelector "[data-key='#{focused}']"
    again?.focus preventScroll: true
    again?.select?()
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

# The tabs & levers only show on the sheet you're reaching for: point at the strip above it or the margin to its left —
# or at the sheet's own blank margin along its top & left edges, so they're already there as you head for them.
# On a touch screen, tap there and they stay up for a few seconds.
toolsPage = null
toolsTimer = null
peripheral = ".edge, .strip, .page > .flag, .page > .lever.spacing"

minimumBand = 16 # CSS px — even with a margin of nothing, there's this much of the sheet's edge to point at

toolsPageAt = (e)->
  if zone = e.target.closest peripheral
    return zone.closest ".page"
  page = e.target.closest ".page"
  return null unless page?
  rect = page.getBoundingClientRect()
  top = Math.max minimumBand, geo.top / linesPerInch * pxPerInch
  left = Math.max minimumBand, geo.left / charactersPerInch * pxPerInch
  if e.clientY - rect.top < top or e.clientX - rect.left < left then page else null

showTools = (page)->
  page = null if viewing
  return if page is toolsPage
  toolsPage?.classList.remove "tools"
  toolsPage = page
  page?.classList.add "tools"

pagesElm.addEventListener "pointermove", (e)->
  return if e.pointerType is "touch" or drag? or pointer?
  showTools toolsPageAt e
pagesElm.addEventListener "pointerleave", (e)-> showTools null unless e.pointerType is "touch" or drag?

pagesElm.addEventListener "pointerdown", (e)->
  return unless e.pointerType is "touch"
  page = toolsPageAt e
  clearTimeout toolsTimer
  if page?
    showTools page
    toolsTimer = setTimeout (()-> showTools null unless drag?), 4000
  else
    showTools null
, true

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

# Margins are measured in from their own edge. Linked margins mirror each other, so they can't cross in the middle.
maxLinkedInset = (kind)->
  if kind in ["left", "right"] then Math.ceil(geo.cols / 2) - 1 else Math.floor (geo.rows - 1) / 2

setInset = (kind, inset)->
  changes =
    if kind in ["left", "right"] and settings.linkLeftRight
      inset = clamp inset, 0, maxLinkedInset kind
      left: inset, right: inset
    else if kind in ["top", "bottom"] and settings.linkTopBottom
      inset = clamp inset, 0, maxLinkedInset kind
      top: inset, bottom: inset
    else switch kind
      when "left" then left: clamp inset, 0, geo.right - 1
      when "right" then right: clamp inset, 0, geo.cols - geo.left - 1
      when "top" then top: clamp inset, 0, geo.rows - geo.bottom - 1
      when "bottom" then bottom: clamp inset, 0, geo.rows - geo.top - 1
  changeSettings changes if Object.keys(changes).some (k)-> settings[k] isnt changes[k]

# Linking snaps the opposite margin to match the one whose link you clicked
toggleLink = (kind)->
  pair = if kind in ["left", "right"] then "linkLeftRight" else "linkTopBottom"
  if settings[pair]
    changeSettings "#{pair}": false
  else
    inset = switch kind
      when "left" then geo.left
      when "right" then geo.cols - geo.right
      when "top" then geo.top
      when "bottom" then geo.bottom
    settings[pair] = true
    setInset kind, inset
    changeSettings {}

moveDrag = (e)->
  switch drag.kind
    when "left" then setInset "left", colAt drag.page, e
    when "right" then setInset "right", geo.cols - colAt drag.page, e
    when "tab"
      drag.removing = Math.abs(e.clientY - drag.y) > 30
      tabs = settings.tabs.slice()
      tabs[drag.index] = clamp colAt(drag.page, e), geo.left + 1, geo.right - 1
      Object.assign settings, {tabs}
      save "settings", settings
      invalidate()
    when "top" then setInset "top", lineAt drag.page, e
    when "bottom" then setInset "bottom", geo.rows - lineAt drag.page, e

endDrag = ()->
  tabs = settings.tabs.slice()
  tabs.splice drag.index, 1 if drag.kind is "tab" and drag.removing
  drag = null
  changeSettings {tabs}
  showGuides false

pagesElm.addEventListener "pointerdown", (e)->
  page = e.target.closest ".page"
  return unless page?
  if link = e.target.closest ".link"
    e.preventDefault()
    e.stopPropagation()
    toggleLink link.closest(".flag").dataset.kind
  else if handle = e.target.closest ".vstop, .flag.down, .tabstop"
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
# Selections are given in printed characters, and mapped onto the Markdown underneath.
# follow: slide the carriage to the new strike point (for the keyboard, but not for pointing at the page)
setSelection = (anchor, focus, follow = true)->
  anchor = clamp anchor, 0, layout.n
  focus = clamp focus, 0, layout.n
  if focus < anchor
    input.setSelectionRange rawAt(focus), rawAt(anchor), "backward"
  else
    input.setSelectionRange rawAt(anchor), rawAt(focus), "forward"
  renderSelection()
  followCaret() if follow

getAnchorFocus = ()->
  [a, b] = selected()
  if input.selectionDirection is "backward" then [b, a] else [a, b]

# Left & right step over the printed characters, skipping the Markdown markers
moveHorizontally = (dir, extend)->
  [anchor, focus] = getAnchorFocus()
  if anchor isnt focus and not extend
    k = if dir < 0 then Math.min(anchor, focus) else Math.max(anchor, focus)
    setSelection k, k
  else
    k = clamp focus + dir, 0, doc.text.length
    setSelection (if extend then anchor else k), k

insertText = (str)->
  # execCommand keeps the browser's undo history intact
  unless document.execCommand "insertText", false, str
    input.setRangeText str, input.selectionStart, input.selectionEnd, "end"
    input.dispatchEvent new Event "input"

# Up & down go a row of type at a time — across a table, to whichever cell is under the caret
moveVertically = (rows, extend)->
  [anchor, focus] = getAnchorFocus()
  goalCol ?= layout.pos[focus][2]
  target = layout.rowKeys.indexOf(rowKey layout.lines[lineIndexOf focus]) + rows
  newFocus =
    if target < 0 then 0
    else if target >= layout.rowKeys.length then layout.n
    else indexAtCol runNearest(layout.rowRuns.get(layout.rowKeys[target]), goalCol), goalCol
  setSelection (if extend then anchor else newFocus), newFocus

moveToLineEdge = (end, extend)->
  [anchor, focus] = getAnchorFocus()
  ln = layout.lines[lineIndexOf focus]
  newFocus = if end then ln.end else ln.start
  setSelection (if extend then anchor else newFocus), newFocus

isMac = /Mac|iPhone|iPad/.test navigator.platform

input.addEventListener "keydown", (e)->
  return if e.isComposing or e.keyCode is 229 # keys that are part of an accent or input method go to it
  mod = if isMac then e.metaKey else e.ctrlKey
  verticalKey = e.key in ["ArrowUp", "ArrowDown", "PageUp", "PageDown"]
  goalCol = null unless verticalKey

  if e.key is "Tab" and not (e.ctrlKey or e.metaKey or e.altKey)
    e.preventDefault()
    if inTable focusIndex() then tabToCell e.shiftKey
    else insertText "\t" unless e.shiftKey
  else if e.key is "Enter" and (e.metaKey or e.ctrlKey)
    e.preventDefault()
    typeText "\f" # Feed in a fresh sheet
  else if e.key in ["ArrowLeft", "ArrowRight"] and not (e.altKey or e.ctrlKey or e.metaKey)
    e.preventDefault()
    moveHorizontally (if e.key is "ArrowLeft" then -1 else 1), e.shiftKey
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

input.addEventListener "input", (e)->
  reparse()
  saveText()
  syncTitle()
  publishSoon()
  render()
  followCaret() unless applying or composing # A rewrite puts the selection back itself, and decides whether to follow it

# While an accent or input method is part way through, leave the textarea and its caret be: moving either can make the
# browser give up on what's being composed
composing = false
input.addEventListener "compositionstart", ()-> composing = true
input.addEventListener "compositionend", ()->
  composing = false
  renderSelection()
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
  return if e.target.closest ".strip, .vstop, .lever"
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
  e.preventDefault() if e.target.closest(".page")

pagesElm.addEventListener "pointercancel", ()->
  pointer = null
  pagesElm.classList.remove "sliding"

window.addEventListener "resize", ()-> render()

# PAGES & LINKS ###################################################################################

# Every page lives at its own link, /s/<id>, and is saved there as it's typed, so it's always ready to share. Anyone
# with the link sees the page as it stands, read-only. The browser that made a page keeps its key and can edit it:
# Edit brings up the machine, and Save (the same key) puts it away again. Anyone else's Edit makes them a copy of
# their own.
# Visiting the site itself goes back to the page you were last working on, or feeds in a fresh one.

editKey = $ ".edit-key"
savedLabel = $ ".saved"

shares = load "shares", {} # id → key, for each page made here
pageId = null # the page on the machine
pageUpdated = null # when the server's copy of it last changed, as far as we know
published = null # what the server was last sent, so an unchanged page isn't sent again
pageMissing = false # a link with no page behind it
publishTimer = null
publishing = false
publishAgain = false

randomString = (n, alphabet)-> (alphabet[v % alphabet.length] for v in crypto.getRandomValues new Uint32Array n).join ""
pageUrl = (id)-> "#{location.origin}/s/#{id}"
pageBody = ()-> JSON.stringify markdown: input.value, settings: settings
pageTitle = ()-> (doc.text.split(/[\n\f]/).find((line)-> line.trim()) ? "").replace(/[\u001F ]/g, " ").trim()
owns = (id)-> id? and shares[id]?

# A new page, with a key only this browser has
makePage = ()->
  id = randomString 10, "abcdefghjkmnpqrstuvwxyz23456789"
  shares[id] = randomString 32, "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz0123456789"
  save "shares", shares
  id

# Each page you make is also kept here, so nothing's lost if it can't reach the server for a while.
# pending means it has changes the server hasn't got yet.
cachePage = (pending)->
  save "page:#{pageId}", {markdown: input.value, settings, pending} if owns pageId
cachedPage = (id)-> load "page:#{id}", null

# Put a page on the machine
loadPage = (id, page)->
  pageId = id
  pageUpdated = page.updated ? null
  settings = Object.assign structuredClone(defaults), page.settings
  normalize()
  input.value = page.markdown ? ""
  reparse()
  published = if page.pending then null else pageBody()
  syncControls()
  syncTitle()
  invalidate()

syncTitle = ()->
  title = pageTitle()
  document.title = if title then "#{title} — Senatorial" else "Senatorial"

# Reading a page, or typing on it
setMode = (edit)->
  viewing = not edit
  document.body.classList.toggle "viewing", viewing
  input.readOnly = viewing
  caretElm.hidden = viewing
  gutterL = if viewing then 16 else 64
  editKey.textContent = if not viewing then "Save" else if owns pageId then "Edit" else "Edit a copy"
  editKey.hidden = pageMissing and not owns pageId
  if viewing
    formatMenu.hidden = true
    showTools null
    input.blur()
    render()
    slideCarriage 0
  else
    save "current", pageId
    render()
    input.focus preventScroll: true
    setSelection layout.n, layout.n
    updateFocus()

# The machine's height, so the sheets keep clear of it
new ResizeObserver(()-> document.documentElement.style.setProperty "--deck-height", "#{deckElm.offsetHeight}px").observe deckElm

editKey.onclick = ()->
  unless viewing
    publish()
    return setMode false
  if owns pageId
    # Changes made in another window that haven't reached the server yet
    cached = cachedPage pageId
    loadPage pageId, cached if cached?.pending
  else
    # Someone else's page: make a copy of your own, at its own link
    copy = {markdown: input.value, settings: structuredClone(settings), pending: true}
    id = makePage()
    history.pushState null, "", "/s/#{id}"
    loadPage id, copy
    cachePage true
    publish()
  setMode true

# A fresh sheet, at a new link. The page that was on the machine stays at its own.
$("#new").onclick = ()->
  publish()
  id = makePage()
  history.pushState null, "", "/s/#{id}"
  loadPage id, {markdown: "", settings: structuredClone(settings), pending: true}
  cachePage true
  setMode true

# Back & forward go between pages
window.addEventListener "popstate", ()-> location.reload()

# Changes reach the server a moment after they're made
publishSoon = ()->
  return unless owns(pageId) and not viewing
  clearTimeout publishTimer
  publishTimer = setTimeout publish, 1500

publish = ()->
  clearTimeout publishTimer
  publishTimer = null
  return unless owns pageId
  return publishAgain = true if publishing
  body = pageBody()
  return if body is published
  id = pageId
  publishing = true
  savedLabel.textContent = "Saving…"
  try
    res = await fetch "/api/shares/#{id}",
      method: "PUT"
      headers: {"content-type": "application/json", authorization: "Bearer #{shares[id]}"}
      body: body
      keepalive: body.length < 60000 # so it still goes out if the page is closing
  catch
    res = null
  publishing = false
  if id is pageId
    if res?.ok
      published = body
      pageUpdated = (await res.json()).updated
      cachePage false if body is pageBody()
      savedLabel.textContent = "Up to date"
    else
      savedLabel.textContent = if res?.status is 403 then "Can't save this page" else "Offline — will keep trying"
      publishTimer = setTimeout publish, 10000 unless res?.status is 403
  if publishAgain
    publishAgain = false
    publish()

document.addEventListener "visibilitychange", ()-> publish() if document.hidden and publishTimer?

# While reading a page, it picks up the latest version every so often, and on coming back to it
refreshPage = ()->
  return unless viewing and pageId? and not document.hidden
  try
    res = await fetch "/api/shares/#{pageId}", cache: "no-store"
  catch
    return
  return unless res.ok and viewing
  page = await res.json()
  loadPage pageId, page unless page.updated is pageUpdated

setInterval refreshPage, 30000
document.addEventListener "visibilitychange", refreshPage

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

$("#export").onclick = ()->
  link = document.createElement "a"
  link.href = URL.createObjectURL new Blob [input.value], type: "text/markdown"
  link.download = "senatorial.md"
  link.click()
  setTimeout ((url)-> ()-> URL.revokeObjectURL url)(link.href), 1000

# Import a Markdown (or plain text) file in place of what's on the page. It goes through the undo history,
# so Undo brings back what was there. Dropping a file on the page does the same.
importFile = $ "#importFile"
$("#import").onclick = ()-> importFile.click()
importFile.onchange = ()->
  file = importFile.files[0]
  importFile.value = ""
  loadMarkdown await file.text() if file?

isTextFile = (file)-> /\.(md|markdown|txt|text)$/i.test(file.name) or file.type.startsWith "text/"

document.addEventListener "dragover", (e)->
  e.preventDefault() if "Files" in Array.from e.dataTransfer?.types ? []
document.addEventListener "drop", (e)->
  file = Array.from(e.dataTransfer?.files ? []).find isTextFile
  return unless file?
  e.preventDefault()
  loadMarkdown await file.text()

loadMarkdown = (md)->
  return if viewing
  replaceRaw 0, input.value.length, md.replace /\r\n?/g, "\n"
  setSelection 0, 0, false
  slideCarriage 0
  window.scrollTo 0, 0

# Each sheet prints on paper of its own size, the way it's fed in, and fills it. Safari keeps to whatever paper is
# picked in its print dialog, so there, if that's bigger than the sheet, the sheet comes out at its true size in the
# middle, with trim marks at the corners to cut it out by. (Chrome measures print media queries against the window,
# not the paper, so the marks are left to Safari, which measures them against the paper. The room above the sheet is a
# border, not a margin, since a margin at the top of a printed page is dropped.)
isSafari = /^((?!chrome|chromium|crios|fxios|android).)*safari/i.test navigator.userAgent

$("#print").onclick = ()->
  printElm = $ ".print"
  printElm.innerHTML = ""
  style = document.createElement "style"
  style.textContent = """
    @page { size: #{geo.w}in #{geo.h}in; margin: 0; }
    .print .leaf { width: #{geo.w}in; height: #{geo.h}in; }
  """
  style.textContent += """
    @media print and (min-width: #{geo.w + 0.8}in), print and (min-height: #{geo.h + 0.9}in) {
      .print .leaf { box-sizing: content-box; margin: 0 auto; border-top: .5in solid transparent; }
      .print .trim { display: block; }
    }
  """ if isSafari
  printElm.append style
  for _, p in layout.pages
    leaf = document.createElement "div"
    leaf.className = "leaf"
    img = new Image()
    img.src = URL.createObjectURL await toBlob renderPageAtExportSize p
    await img.decode()
    leaf.append img, trimMarks()...
    printElm.append leaf
  window.print()

# A pair of short lines off each corner, lined up with the sheet's edges, an eighth of an inch clear of them
trimMarks = ()->
  marks = []
  for x in [0, 1]
    for y in [0, 1]
      across = document.createElement "div"
      across.className = "trim across"
      across.style.top = "#{y * 100}%"
      across.style.left = if x then "calc(100% + .125in)" else "-.375in"
      down = document.createElement "div"
      down.className = "trim down"
      down.style.left = "#{x * 100}%"
      down.style.top = if y then "calc(100% + .125in)" else "-.375in"
      marks.push across, down
  marks

# GO ##############################################################################################

# What was on the machine before pages had links: Markdown, or (from older versions still) plain text with a separate
# styles string, which is written out as Markdown here
legacyText = ()->
  text = (try localStorage.getItem "text") ? ""
  return text if (try localStorage.getItem "format") is "markdown"
  oldStyles = (try localStorage.getItem "styles") ? ""
  version = (try localStorage.getItem "stylesVersion") ? "1"
  oldStyles = "" unless oldStyles.length is text.length
  chars = Array.from text
  codes = for c, i in text
    # v1: weight×2 + red + 6·centred, in base 36. v2: the same, plus 12·caps + 24·underline, as a char code from "0".
    v = if not oldStyles[i]? then 0 else if version is "2" then oldStyles.charCodeAt(i) - 48 else parseInt oldStyles[i], 36
    chars[i] = c.toUpperCase() if v % 24 >= 12 and c.toUpperCase().length is 1
    encodeStyle weight: weights[(v % 6) >> 1], red: (v & 1) is 1, center: v % 12 >= 6, underline: v >= 24
  serializeBlock chars.join(""), codes.join("") + encodeStyle {}

settings = Object.assign structuredClone(defaults), load "settings", {}
normalize()
loadAtlases()

if m = location.pathname.match /^\/s\/([a-z0-9]{6,32})\/?$/
  # A page's link: read it — or, if it's yours and has changes the server hasn't got yet, pick up where you left off
  id = m[1]
  cached = cachedPage id if owns id
  if cached?.pending
    loadPage id, cached
  else if shared? and not shared.missing
    loadPage id, shared
  else if owns id
    loadPage id, cached ? {markdown: "", settings, pending: true}
  else
    pageMissing = true
    loadPage id, {markdown: "->There's no page here.<-"}
  setMode false
  publish()
else
  # The site itself: back to the page you were last working on, or a fresh one. The first picks up whatever was on
  # the machine before pages had links (and the link it was shared at, if it was).
  id = load "current", null
  id = load "sharing", null unless owns id
  page = cachedPage id if owns id
  unless page?
    id = makePage() unless owns id
    page = {markdown: legacyText(), settings, pending: true}
    try localStorage.removeItem key for key in ["text", "format", "styles", "stylesVersion", "sharing"]
  history.replaceState null, "", "/s/#{id}"
  loadPage id, page
  cachePage page.pending ? false
  setMode true
  publish()
