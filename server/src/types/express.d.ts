// Declaration merging: add `req.user` to Express's Request type so the auth
// middleware can set it and routes can read it with full typing. The
// `export {}` makes this file a module, which `declare global` requires.
import type { AuthUser } from "../middleware/auth.js";

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export {};
