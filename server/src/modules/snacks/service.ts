import type { Snack } from "../../../../shared/types.js";
import prisma from "../../db.js";
import { getAllSnacks } from "./repo.js";

export async function getSnacks(): Promise<Snack[]> {
  const snacks = await getAllSnacks(prisma);
  return snacks
    .filter((row) => row.is_available && !row.is_retired)
    .map((row) => {
      return {
        id: row.id.toString(),
        name: row.name,
        price: row.price.toString(),
      };
    });
}
