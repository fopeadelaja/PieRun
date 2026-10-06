import { Router } from "express";
import { getSnacks } from "./service.js";
import type { ApiResponse, Snack } from "../../../../shared/types.js";

const router = Router();

router.get("/", async (req, res) => {
  const snacks = await getSnacks();
  const body: ApiResponse<Snack[]> = { data: snacks };
  res.json(body);
});

export default router;
