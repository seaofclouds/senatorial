-- Shared pages: a short link that always shows the latest version of a page, read-only.
-- Whoever shared the page holds the key to update it; only a hash of the key is kept.
CREATE TABLE IF NOT EXISTS shares (
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL,
  markdown TEXT NOT NULL,
  settings TEXT NOT NULL,
  created INTEGER NOT NULL,
  updated INTEGER NOT NULL
);
