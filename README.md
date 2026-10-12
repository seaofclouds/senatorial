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
  done the typist's way, by striking another key over the letters. The alignment lever centres the paragraph you're in.
- The margin tabs, tab stops, and line space lever stay hidden until you point at the strip above a sheet or the margin
  to its left (on a phone, tap there).
- Tap the paper size in the corner of the sheet to feed in a different kind of paper.
- The line space lever, under the top margin tab, sets single, 1½, or double spacing.
- ⌘/Ctrl+Enter feeds a fresh sheet. Save downloads 600 dpi PNGs; Print prints at the exact sheet size.

## The text is Markdown

What's on the page is stored, copied, and saved (with the Markdown button) as plain Markdown. The markers are invisible
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

Capitals are typed over the letters themselves, like shift lock. A backslash before a marker character prints it as is.

## Running it

There's no build step — `index.coffee` is compiled in the browser by `coffeescript.js`.
Serve the folder with any static server, e.g. `npx http-server .`

## Deploying

Pushes to `main` deploy to the `senatorial` Cloudflare Worker via Workers Builds,
using `wrangler.jsonc` to serve this folder as static assets.
