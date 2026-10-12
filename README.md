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
- The paper key, on the left of the control bar, lays out every kind of paper on the desk to feed in.
- The line space lever, under the top margin tab, sets single, 1½, or double spacing.
- ⌘/Ctrl+Enter feeds a fresh sheet. Save downloads 600 dpi PNGs; Print prints at the exact sheet size.

## The text is Markdown

What's on the page is stored, copied, and exported (with the Export key) as plain Markdown. Import opens a Markdown or
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

## Sharing

The Share key gives the page a short link (on a phone, it brings up the share sheet). Whoever opens it sees the page
as it is on your machine — read-only, but always the latest version: every change is sent to the link a moment after
you make it, and an open link picks it up when they come back to it. They can save, print, or export it.

The link belongs to the page that was on the machine when you shared it. Importing another page or resetting the
machine stops sending changes to it (Undo picks it back up), and Stop sharing, on the slip the Share key opens, takes
the link down. The browser you shared from keeps the key to the page, so opening your own link there offers an Edit
key that brings the page back onto the machine.

## Running it

There's no build step — `index.coffee` is compiled in the browser by `coffeescript.js`.
Serve the folder with any static server, e.g. `npx http-server .` — or, to try sharing too,
`npx wrangler d1 migrations apply senatorial-shares --local --persist-to ../.senatorial-state` and then
`npx wrangler dev --persist-to ../.senatorial-state` (keeping the local database outside the folder being served).

## Deploying

Pushes to `main` deploy to the `senatorial` Cloudflare Worker via Workers Builds, using `wrangler.jsonc` to serve
this folder as static assets, with `worker.js` handling shared pages (`/s/…`) and their API (`/api/shares/…`).
Shared pages are kept in the `senatorial-shares` D1 database; its table is in `migrations/`.
