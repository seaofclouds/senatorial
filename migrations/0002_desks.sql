-- A page can belong to a desk: every page typed in one browser, or in any browser the desk's link has been opened in.
-- Only a hash of the desk's key is kept.
ALTER TABLE shares ADD COLUMN owner_hash TEXT;
CREATE INDEX IF NOT EXISTS shares_owner ON shares (owner_hash, updated);
