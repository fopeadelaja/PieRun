import { Router } from "express";
import type { ApiResponse, User } from "../../../../shared/types.js";
import { BadRequestError } from "../../errors.js";
import { registerUser, loginUser } from "./service.js";

const router = Router();

// Same rules as the CHECK constraints in 003_name_format.sql. The database
// is the guard; these exist so the client gets a 400 with a reason instead
// of a 500 from a constraint violation.
const USERNAME_MIN_LENGTH = 3;
const USERNAME_RE = /^[A-Za-z0-9]+([._][A-Za-z0-9]+)*$/;
// \p{L} is "any letter in any script"; needs the u flag. Postgres's
// [[:alpha:]] is the equivalent on the database side.
const NAME_RE = /^\p{L}+([ '-]\p{L}+)*$/u;

// req.body is whatever the client sent; treat it as unknown until checked.
function requireString(body: unknown, field: string): string {
  const value = (body as Record<string, unknown>)[field];
  if (typeof value !== "string" || value.trim() === "") {
    throw new BadRequestError(`${field} is required`);
  }
  return value.trim();
}

function requireUsername(body: unknown): string {
  const value = requireString(body, "username");
  if (value.length < USERNAME_MIN_LENGTH) {
    throw new BadRequestError(
      `username must be at least ${USERNAME_MIN_LENGTH} characters`,
    );
  }
  if (!USERNAME_RE.test(value)) {
    throw new BadRequestError(
      "username may only contain letters, digits, '.' and '_', and '.' or '_' may not start, end, or repeat",
    );
  }
  return value;
}

function requireName(body: unknown, field: string): string {
  const value = requireString(body, field);
  if (!NAME_RE.test(value)) {
    throw new BadRequestError(
      `${field} may only contain letters, single spaces, hyphens and apostrophes`,
    );
  }
  return value;
}

router.post("/register", async (req, res) => {
  const username = requireUsername(req.body);
  const password = requireString(req.body, "password");
  const firstName = requireName(req.body, "firstName");
  const lastName = requireName(req.body, "lastName");

  const user = await registerUser({ username, password, firstName, lastName });
  const body: ApiResponse<User> = { data: user };
  res.status(201).json(body);
});

router.post("/login", async (req, res) => {
  // Only presence is checked here: a malformed username simply won't match
  // any user and gets the same 401 as a wrong password.
  const username = requireString(req.body, "username");
  const password = requireString(req.body, "password");

  const token = await loginUser(username, password);
  res.cookie("token", token, { httpOnly: true, sameSite: "lax" });
  res.sendStatus(204);
});

export default router;
