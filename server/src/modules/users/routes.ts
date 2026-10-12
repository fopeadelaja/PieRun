import { Router } from "express";
import type { ApiResponse, User } from "../../../../shared/types.js";
import { ValidationError } from "../../errors.js";
import { requireAuth } from "../../middleware/auth.js";
import { getUserById, registerUser, loginUser } from "./service.js";

const router = Router();

// The route checks the *shape* of the request: is the field there, is it a
// string. What makes a username or name valid is a domain rule and lives in
// the service, so every caller gets it, not only HTTP.
function requireString(body: unknown, field: string): string {
  const value = (body as Record<string, unknown>)[field];
  if (typeof value !== "string" || value.trim() === "") {
    throw new ValidationError(`${field} is required`);
  }
  return value;
}

router.post("/register", async (req, res) => {
  const user = await registerUser({
    username: requireString(req.body, "username"),
    password: requireString(req.body, "password"),
    firstName: requireString(req.body, "firstName"),
    lastName: requireString(req.body, "lastName"),
  });
  const body: ApiResponse<User> = { data: user };
  res.status(201).json(body);
});

router.post("/login", async (req, res) => {
  const token = await loginUser(
    requireString(req.body, "username"),
    requireString(req.body, "password"),
  );
  res.cookie("token", token, { httpOnly: true, sameSite: "lax" });
  res.sendStatus(204);
});

// First protected route. requireAuth runs before the handler and either
// sets req.user or throws 401; the handler never sees an anonymous request.
router.get("/me", requireAuth, async (req, res) => {
  const user = await getUserById(req.user!.userId);
  const body: ApiResponse<User> = { data: user };
  res.json(body);
});

router.post("/logout", (_req, res) => {
  res.clearCookie("token");
  res.sendStatus(204);
});

export default router;
