# Senatorial

A typewriter you type on directly. Every letter is struck from scans of a real Senatorial typeface,
onto true-to-size sheets of paper at 11 characters and 6 lines to the inch.

- Click the paper to place the carriage, and type.
- Drag the margin stops on the scale; click the scale to set a tab, pull a tab off to clear it.
- The top & bottom margin stops (in lines) sit along the left edge of each sheet.
- Tap the paper size in the corner of the sheet to feed in a different kind of paper.
- The line space lever sets single, 1½, or double spacing.
- ⌘/Ctrl+Enter feeds a fresh sheet. Save downloads 600 dpi PNGs; Print prints at the exact sheet size.

## Running it

There's no build step — `index.coffee` is compiled in the browser by `coffeescript.js`.
Serve the folder with any static server, e.g. `npx http-server .`

## Deploying

Pushes to `main` deploy to the `senatorial` Cloudflare Worker via Workers Builds,
using `wrangler.jsonc` to serve this folder as static assets.
