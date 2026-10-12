import type { Snack } from "../../../../shared/types.js";
import type { Db } from "../../db.js";
import prisma from "../../db.js";
import { findOrderableByIds, getAllSnacks } from "./repo.js";

// What another module gets when it asks about snacks for an order. Price
// stays a Decimal here: this never crosses the wire, and the orders service
// does arithmetic with it.
export type OrderableSnack = {
  id: bigint;
  name: string;
  price: Awaited<ReturnType<typeof getAllSnacks>>[number]["price"];
};

// The module boundary for orders: it calls this, never the snacks table.
// Takes a Db so the caller can pass its transaction handle. Returns only
// the orderable snacks it found; missing ids are the caller's problem.
export async function getForOrder(
  db: Db,
  ids: string[],
): Promise<OrderableSnack[]> {
  const rows = await findOrderableByIds(
    db,
    ids.map((id) => BigInt(id)),
  );
  return rows.map((row) => ({ id: row.id, name: row.name, price: row.price }));
}

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
