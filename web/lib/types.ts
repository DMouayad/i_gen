// Shared shapes for the orders domain (server columns, Phase 10/12).
// Prices never surface here: distributors order blind (price written as 0).

export interface Product {
  id: string;
  model: string;
  name: string;
  sizes: string[];
}

export function parseProduct(row: Record<string, unknown>): Product | null {
  if (
    typeof row["id"] !== "string" ||
    typeof row["model"] !== "string" ||
    typeof row["name"] !== "string"
  ) {
    return null;
  }
  const raw = row["sizes"];
  let sizes: string[] = [];
  if (typeof raw === "string") {
    try {
      const parsed: unknown = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        sizes = parsed.filter(
          (s): s is string => typeof s === "string",
        );
      }
    } catch {
      sizes = [];
    }
  } else if (Array.isArray(raw)) {
    sizes = raw.filter((s): s is string => typeof s === "string");
  }
  return { id: row["id"], model: row["model"], name: row["name"], sizes };
}

export interface CartLine {
  productId: string;
  model: string;
  name: string;
  /** '' = sizeless (matches invoice_lines/order_items wire form). */
  size: string;
  qty: number;
}

export type OrderStatus = "pending" | "confirmed" | "delivered" | "cancelled";

export interface OrderRow {
  id: string;
  status: string;
  total: number;
  currency: string;
  created_at: string | null;
}

export interface OrderItemRow {
  id: string;
  order_id: string;
  product_id: string | null;
  amount: number;
  price: number;
  size: string;
}

export function parseOrder(row: Record<string, unknown>): OrderRow | null {
  if (
    typeof row["id"] !== "string" ||
    typeof row["status"] !== "string" ||
    typeof row["total"] !== "number" ||
    typeof row["currency"] !== "string"
  ) {
    return null;
  }
  const created = row["created_at"];
  return {
    id: row["id"],
    status: row["status"],
    total: row["total"],
    currency: row["currency"],
    created_at: typeof created === "string" ? created : null,
  };
}
