# Senatorial

A typewriter you type on directly. Every letter is struck from scans of a real Senatorial typeface,
onto true-to-size sheets of paper at 11 characters and 6 lines to the inch.

- Click the paper to place the carriage, and type.
- Sheets are shown at actual size. When one is wider than the screen, it slides with the carriage as you type.
- The left & right margin tabs sit above the sheet, the top & bottom ones (in lines) along its left edge — drag them.
  Click the strip above the sheet to set a tab stop; drag one away to clear it.
- On a phone, swipe sideways to slide the sheet. The red mark above the sheet is its centre.
- Select text to restrike it light, double struck, or in red. The alignment lever centres the paragraph you're in.
- Tap the paper size in the corner of the sheet to feed in a different kind of paper.
- The line space lever, under the top margin tab, sets single, 1½, or double spacing.
- ⌘/Ctrl+Enter feeds a fresh sheet. Save downloads 600 dpi PNGs; Print prints at the exact sheet size.

## Running it

There's no build step — `index.coffee` is compiled in the browser by `coffeescript.js`.
Serve the folder with any static server, e.g. `npx http-server .`

## Deploying

Pushes to `main` deploy to the `senatorial` Cloudflare Worker via Workers Builds,
using `wrangler.jsonc` to serve this folder as static assets.
