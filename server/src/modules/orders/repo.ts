import { Prisma } from "../../../generated/prisma/client.js";
import type { Db } from "../../db.js";

type AcceptData = {
  total: Prisma.Decimal;
  fulfillmentDate: Date;
  acceptedAt: Date;
};

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

export function findByIdForUser(db: Db, orderId: bigint, userId: bigint) {
  return db.orders.findFirst({
    where: { id: orderId, user_id: userId },
    include: { order_items: true },
  });
}

export async function acceptIfPending(
  db: Db,
  orderId: bigint,
  data: AcceptData,
) {
  const result = await db.orders.updateMany({
    where: { id: orderId, status: "PENDING" },
    data: {
      total: data.total,
      fulfillment_date: data.fulfillmentDate,
      accepted_at: data.acceptedAt,
      status: "ACCEPTED",
    },
  });
  return result.count;
}
