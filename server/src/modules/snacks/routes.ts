import { Router } from "express";
import { getSnacks } from "./service.js";

const router = Router();

router.get("/", async (req, res) => {
  const snacks = await getSnacks();
  res.json({ data: snacks });
});

export default router;
