import type { Db } from "../../db.js";

export function getAllSnacks(db: Db) {
  return db.snacks.findMany({ orderBy: { name: "asc" } });
}
