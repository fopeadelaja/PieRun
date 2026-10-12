import type { Db } from "../../db.js";

export function getAllSnacks(db: Db) {
  return db.snacks.findMany({ orderBy: { name: "asc" } });
}

// Only snacks that can be ordered right now. Ids that are unknown, retired
// or unavailable are simply absent from the result; the caller decides what
// that means.
export function findOrderableByIds(db: Db, ids: bigint[]) {
  return db.snacks.findMany({
    where: { id: { in: ids }, is_available: true, is_retired: false },
  });
}
