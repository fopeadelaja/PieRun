-- ============================================================================
-- 003 — format rules for username and names (R8a, R8b)
--
-- Validate at the database, normalise in the application. The app trims and
-- lowercases before insert and repeats these checks for a friendly 400; the
-- constraints here are the guard that cannot be bypassed.
--
--   username:  letters/digits, with '.' or '_' allowed only singly and only
--              between letters/digits — never at either end, never doubled.
--   names:     letters (any script), joined by single spaces, hyphens or
--              apostrophes — e.g. "Mary Ann", "Jean-Luc", "O'Brien".
-- ============================================================================
BEGIN;

ALTER TABLE users
  ADD CONSTRAINT username_min_length CHECK (length(username) >= 3),
  ADD CONSTRAINT username_format
    CHECK (username ~ '^[A-Za-z0-9]+([._][A-Za-z0-9]+)*$'),
  ADD CONSTRAINT first_name_format
    CHECK (first_name ~ '^[[:alpha:]]+([ ''-][[:alpha:]]+)*$'),
  ADD CONSTRAINT last_name_format
    CHECK (last_name ~ '^[[:alpha:]]+([ ''-][[:alpha:]]+)*$');

COMMIT;
