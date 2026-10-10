import { Router } from "express";
import { registerUser, loginUser } from "./service.js";

const router = Router();

router.post("/register", async (req, res) => {
  const { username, password, firstName, lastName } = req.body;
  const user = await registerUser({ username, password, firstName, lastName });
  res.status(201).json({ data: user });
});

router.post("/login", async (req, res) => {
  const { username, password } = req.body;
  const token = await loginUser(username, password);
  res.cookie("token", token, { httpOnly: true, sameSite: "lax" });
  res.sendStatus(204);
});

export default router;
