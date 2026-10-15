import type { Order, OrderItem } from "../../../../shared/types.js";
import { Prisma } from "../../../generated/prisma/client.js";
import prisma from "../../db.js";
import { ValidationError } from "../../errors.js";
import { getForOrder } from "../snacks/service.js";
import { createOrder } from "./repo.js";

// ---------------------------------------------------------------------------
// Row → wire
// ---------------------------------------------------------------------------

type ItemRow = {
  snack_id: bigint;
  quantity: number;
  price: Prisma.Decimal | null;
  total: Prisma.Decimal | null;
};

type OrderRow = {
  id: bigint;
  user_id: bigint;
  status: Order["status"];
  estimated_total: Prisma.Decimal;
  total: Prisma.Decimal | null;
  fulfillment_date: Date | null;
  created_at: Date;
  order_items: ItemRow[];
};

function toItem(row: ItemRow): OrderItem {
  return {
    snackId: row.snack_id.toString(),
    quantity: row.quantity,
    price: row.price?.toString() ?? null,
    total: row.total?.toString() ?? null,
  };
}

// A DATE column comes back as a Date at midnight UTC; only the calendar
// part is meaningful, so send YYYY-MM-DD and nothing else.
function toDateString(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function toOrder(row: OrderRow): Order {
  return {
    id: row.id.toString(),
    userId: row.user_id.toString(),
    status: row.status,
    estimatedTotal: row.estimated_total.toString(),
    total: row.total?.toString() ?? null,
    fulfillmentDate: row.fulfillment_date
      ? toDateString(row.fulfillment_date)
      : null,
    createdAt: row.created_at.toISOString(),
    items: row.order_items.map(toItem),
  };
}

// ---------------------------------------------------------------------------
// Submit
// ---------------------------------------------------------------------------

type SubmitItem = { snackId: string; quantity: number };

// Rules that need no database: cheap rejections first.
function validateSubmission(items: SubmitItem[]): void {
  if (items.length === 0) {
    throw new ValidationError("An order needs at least one item"); // R4
  }
  for (const item of items) {
    if (!Number.isInteger(item.quantity) || item.quantity < 1) {
      throw new ValidationError(
        `quantity for snack ${item.snackId} must be a whole number of at least 1`, // F2
      );
    }
  }
  const ids = new Set(items.map((i) => i.snackId));
  if (ids.size !== items.length) {
    throw new ValidationError(
      "A snack may appear only once per order; use quantity instead", // R2
    );
  }
}

export async function submitOrder(
  userId: string,
  items: SubmitItem[],
): Promise<Order> {
  validateSubmission(items);

  return prisma.$transaction(async (tx) => {
    // Through the snacks *service*, never its table (module boundary rule).
    const snacks = await getForOrder(
      tx,
      items.map((i) => i.snackId),
    );
    const priceBySnackId = new Map(snacks.map((s) => [s.id.toString(), s.price]));

    // R7a: anything unknown, retired or unavailable is simply absent.
    const missing = items
      .map((i) => i.snackId)
      .filter((id) => !priceBySnackId.has(id));
    if (missing.length > 0) {
      throw new ValidationError(
        `These snacks cannot be ordered: ${missing.join(", ")}`,
      );
    }

    // D-018: the estimate is today's catalogue prices. Decimal throughout;
    // prices are never JavaScript numbers.
    const estimatedTotal = items.reduce(
      (sum, i) => sum.add(priceBySnackId.get(i.snackId)!.mul(i.quantity)),
      new Prisma.Decimal(0),
    );

    const row = await createOrder(tx, {
      userId: BigInt(userId),
      estimatedTotal,
      items: items.map((i) => ({
        snackId: BigInt(i.snackId),
        quantity: i.quantity,
      })),
    });
    return toOrder(row);
  });
}
