import type { PrismaClient, Prisma } from "../../../generated/prisma/client.js";
type Db = PrismaClient | Prisma.TransactionClient;

export function getAllSnacks(db: Db) {
  return db.snacks.findMany({ orderBy: { name: "asc" } });
}
