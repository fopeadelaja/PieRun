import { Router } from "express";
import { registerUser, loginUser } from "./service.js";

const router = Router();

router.post("/register", async (req, res) => {
  const { username, password, firstName, lastName } = req.body;
  const user = await registerUser({ username, password, firstName, lastName });
  res.json(user);
});

router.post("/login", async (req, res) => {
  const { username, password } = req.body;
  const token = await loginUser(username, password);
  res.json({ token });
});

export default router;
