import type { NextFunction, Request, Response } from "express";
import jwt from "jsonwebtoken";
import { JWT_SECRET } from "../config.js";
import { UnauthorizedError } from "../errors.js";

// What the token carries and what routes get as `req.user`. Kept minimal:
// anything else about the user is one lookup away, and stale claims in a
// seven-day token are a footgun (an admin demoted today stays admin in
// their token until it expires).
export type AuthUser = {
  userId: string;
  isAdmin: boolean;
};

function isAuthUser(payload: unknown): payload is AuthUser {
  return (
    typeof payload === "object" &&
    payload !== null &&
    typeof (payload as AuthUser).userId === "string" &&
    typeof (payload as AuthUser).isAdmin === "boolean"
  );
}

// Reads the httpOnly cookie set by POST /users/login, verifies it, and puts
// the claims on req.user. Any failure (no cookie, bad signature, expired,
// unexpected shape) is the same 401, so nothing is learned from the error.
export function requireAuth(req: Request, _res: Response, next: NextFunction) {
  const token = (req.cookies as Record<string, unknown> | undefined)?.token;
  if (typeof token !== "string") throw new UnauthorizedError();

  let payload: unknown;
  try {
    payload = jwt.verify(token, JWT_SECRET);
  } catch {
    throw new UnauthorizedError();
  }

  if (!isAuthUser(payload)) throw new UnauthorizedError();

  req.user = { userId: payload.userId, isAdmin: payload.isAdmin };
  next();
}

// For admin-only routes: compose after requireAuth.
export function requireAdmin(req: Request, _res: Response, next: NextFunction) {
  if (!req.user?.isAdmin) throw new UnauthorizedError("Admin only");
  next();
}
