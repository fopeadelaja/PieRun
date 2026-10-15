// API types shared by client and server.
// Money and ids are strings on the wire. See CLAUDE.md.

export type ApiResponse<T> = {
  data: T;
};

export type ApiError = {
  error: string;
};

export type Snack = {
  id: string;
  name: string;
  price: string;
};

export type User = {
  id: string;
  username: string;
  firstName: string;
  lastName: string;
  isAdmin: boolean;
};

// Lifecycle only. Payment is a separate, derived state (see CLAUDE.md):
// there is deliberately no PAID here.
export type OrderStatus =
  | "PENDING"
  | "ACCEPTED"
  | "COMPLETED"
  | "REJECTED"
  | "CANCELLED";

export type OrderItem = {
  snackId: string;
  quantity: number;
  // null until the order is accepted, when the price is frozen (S4).
  price: string | null;
  total: string | null;
};

export type Order = {
  id: string;
  userId: string;
  status: OrderStatus;
  estimatedTotal: string;
  // null until accepted (S5, T1).
  total: string | null;
  fulfillmentDate: string | null; // YYYY-MM-DD
  createdAt: string; // ISO 8601
  items: OrderItem[];
};

// What a client sends to POST /orders.
export type SubmitOrderInput = {
  items: { snackId: string; quantity: number }[];
};
