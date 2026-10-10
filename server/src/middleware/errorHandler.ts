import type { NextFunction, Request, Response } from "express";
import type { ApiError } from "../../../shared/types.js";

// Registered after every route in index.ts. Must keep the four-argument
// signature or Express treats it as ordinary middleware.
//
// Our error classes (errors.ts) carry a `status`; the handler trusts that
// and sends the message. Anything without a status is an unexpected 500:
// log the real error here, send the client a generic line.
export function errorHandler(
  err: Error & { status?: number },
  _req: Request,
  res: Response,
  _next: NextFunction,
) {
  const status = err.status ?? 500;
  if (status === 500) console.error(err);

  const body: ApiError = {
    error: status === 500 ? "Internal server error" : err.message,
  };
  res.status(status).json(body);
}
