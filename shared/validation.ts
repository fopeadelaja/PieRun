// Format rules shared by the server (service layer) and the client (form
// feedback). The database enforces the same rules as CHECK constraints in
// server/migrations/003_name_format.sql; keep all three in step.

export const USERNAME_MIN_LENGTH = 3;

// Letters/digits, with '.' or '_' allowed only singly and only between
// letters/digits: never at either end, never doubled.
export const USERNAME_RE = /^[A-Za-z0-9]+([._][A-Za-z0-9]+)*$/;
export const USERNAME_RULE =
  "letters, digits, '.' and '_' only; '.' and '_' may not start, end, or repeat";

// Letters in any script, joined by single spaces, hyphens or apostrophes.
// \p{L} needs the u flag; Postgres uses [[:alpha:]] for the same thing.
export const NAME_RE = /^\p{L}+([ '-]\p{L}+)*$/u;
export const NAME_RULE = "letters, single spaces, hyphens and apostrophes only";
