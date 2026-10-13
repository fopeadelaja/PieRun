import { Prisma } from "../../../generated/prisma/client.js";
import type { Db } from "../../db.js";

type NewOrder = {
  userId: bigint;
  estimatedTotal: Prisma.Decimal;
  items: {
    snackId: bigint;
    quantity: number;
  }[];
};

export function createOrder(db: Db, order: NewOrder) {
  return db.orders.create({
    data: {
      user_id: order.userId,
      estimated_total: order.estimatedTotal,
      order_items: {
        create: [
          ...order.items.map((item) => ({
            snack_id: item.snackId,
            quantity: item.quantity,
          })),
        ],
      },
    },
  });
}
