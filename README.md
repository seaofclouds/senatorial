# Senatorial

A typewriter you type on directly. Every letter is struck from scans of a real Senatorial typeface,
onto true-to-size sheets of paper at 11 characters and 6 lines to the inch.

- Click the paper to place the carriage, and type.
- Sheets are shown at actual size. When one is wider than the screen, it slides with the carriage as you type.
- The left & right margin tabs sit above the sheet, the top & bottom ones (in lines) along its left edge. Each shows how
  far in it is from its own edge — drag them. Click a tab's link to tie it to the opposite margin, so the two mirror each other.
- Click the strip above the sheet to set a tab stop; drag one away to clear it. The mark in the middle is the sheet's centre.
- On a phone, swipe sideways to slide the sheet.
- Select text to restrike it light, double struck, in red, in capitals, underlined, struck through, or X'd out — each
  done the typist's way, by striking another key over the letters. The alignment lever sets the paragraph you're in flush left, centred, or flush right.
- The margin tabs, tab stops, and line space lever stay hidden until you point at the strip above a sheet or the margin
  to its left (on a phone, tap there).
- The paper key, on the left of the control bar, lays out every kind of paper on the desk to feed in, and sets margins
  to suit it: a quarter inch on a card, half an inch or so on A5, an inch on letter. Type in a custom size and Save size
  names it and keeps it on the desk for next time (× forgets it).
- The character key (ñ ½ →), beside the paper key, lays out every character the machine strikes that isn't on the
  keyboard. Click one to type it. Dead keys and input methods work too (Option-N then N for ñ).
- The line space lever, under the top margin tab, sets single, 1½, or double spacing.
- ⌘/Ctrl+Enter feeds a fresh sheet. Export PNG downloads each sheet as a 600 dpi picture.
- Print prints each sheet on paper of its own size and orientation, edge to edge, in Chrome and Edge. Safari
  prints on whatever paper its print dialog has picked, so pick the sheet's size there; if the paper's bigger, the
  sheet comes out at its true size in the middle, with trim marks to cut it out by.

## The text is Markdown

What's on the page is stored, copied, and exported (with Export Markdown) as plain Markdown. Import Markdown opens a Markdown or
text file in its place — or drop one on the page — and Undo brings back what was there. The markers are invisible
on the page and take up no room on the grid — and typing them by hand works too:

| On the page | In Markdown |
| --- | --- |
| Double struck | `**text**` |
| Light | `` `text` `` |
| Underlined | `_text_` or `*text*` |
| Red ribbon | `==text==` |
| Struck through | `~~text~~` |
| X'd out | `~~~text~~~` |
| Centred line | `->text<-` |
| Flush right line | `->text->` |
| Heading — double struck & underlined | `# text` (any level, and it can be centred too: `-># text<-`) |

Capitals are typed over the letters themselves, like shift lock. A backslash before a marker character prints it as is.

A character can also be written by its name or number, the way Markdown and HTML spell them: `&frac12;`, `&rarr;`,
`&#189;`, or `&#xBD;` all print ½ (pointing at a character in the character key shows its name). A character the type
doesn't have is struck with one that looks the same (✔ with ✓, ⇒ with →), and a letter with an accent it doesn't
have is struck as the letter with the accent over it, the way a typist would.

### Tables

A Markdown table sets its cells out in columns across the sheet, with no rules drawn — the way a typist would tab
them out. The header row is just the first line (format it however you like), the delimiter row sets each column
flush left, centred (`:---:`), or flush right (`---:`), and `<br>` breaks a line inside a cell:

```
| _Dutch oven:_ | ==or== | _Slow cooker:_ |
|---|:---:|---|
| simmer on low 2-3 hours<br>stir occasionally | | transfer to slow cooker<br>cook on low 6-8 hours |
```

In a table, Return starts a new line inside the cell (or, at the end of the last cell, leaves the table), Tab and
Shift-Tab select the next and previous cells, Tab in the last cell adds a row, and the alignment lever sets the
column. Columns spread out across the line when they fit, and wrap within a share of it when they don't.

## Every page has a link

Each page lives at its own link, `/s/…`, and is saved there as you type — so whatever's on the page is always ready to
share. Visiting the site takes you to the page you were last working on, and New feeds in a fresh one at a new link
(Back returns to the one before). To share a page, share its link — it's the one in the address bar.

Opening a link shows just the page, in the middle of the screen, with an Edit key in the corner. On a page you made,
Edit brings up the machine, and Save (in the same spot) puts it away again. Anyone else sees the latest version (an open link picks up
changes when they come back to it), and their Edit key makes them a copy of their own, at its own link.

Only the browser a page was made in can change it: it keeps the page's key, and the server keeps just a hash of it.

## Glyphs

Every strike (light, regular and double struck, in black and in red) has one image in `glyphs/`, with the glyphs set
out in a grid in the order `glyphs/layout.json` lists them, at 600 dpi. A character the images don't have types as a
blank space.

They're built by `python3 docs/build-glyphs.py`, from two sources in `scans/`:

- `scans/typed/`: the typewriter's own scans, at 1200 dpi.
- `scans/character-sheet-black.png` and `scans/character-sheet-red.png`: the filled-in character sheets, with
  everything the typewriter doesn't have drawn by hand.

`docs/character-sheet.pdf` and `docs/character-sheet-red.pdf` are those sheets, blank (`python3 docs/character-sheet.py`
rebuilds them). They lay out every character at true size in each strike: the typed glyphs, and a blank for each one to
draw. Accents are drawn once each, over a capital and over a lowercase letter, after a typed letter to line them up
against. To add or redraw glyphs, print a sheet at actual size, draw in the blanks, scan it at 1200 dpi into `scans/`,
and run the build. It lines the scan up against the typed glyphs and cuts out each drawing. Every drawing in a weight is
scaled by the same amount, the one that brings its drawn capitals and x-height letters to the typed ones' size, so all
of them keep the weight of the pen they were drawn with. Each is set at the height its kind of character sits at (on
the baseline, raised, centred, or hanging below), centred across its cell. Then it lays each accent over every letter
that takes it.

## Running it

There's no build step — `index.coffee` is compiled in the browser by `coffeescript.js`.
Pages are saved to their links by `worker.js`, so to run it all locally,
`npx wrangler d1 migrations apply senatorial-shares --local --persist-to ../.senatorial-state` and then
`npx wrangler dev --persist-to ../.senatorial-state` (keeping the local database outside the folder being served).
Any static server works for just typing, e.g. `npx http-server .`, though nothing is saved to a link that way.

## Deploying

Pushes to `main` deploy to the `senatorial` Cloudflare Worker via Workers Builds, using `wrangler.jsonc` to serve
this folder as static assets, with `worker.js` handling pages' links (`/s/…`) and their API (`/api/shares/…`).
Pages are kept in the `senatorial-shares` D1 database; its table is in `migrations/`.
