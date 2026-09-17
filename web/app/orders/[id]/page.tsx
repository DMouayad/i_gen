"use client";

import Link from "next/link";
import { use, useCallback, useEffect, useState } from "react";
import StatusBadge from "@/app/status-badge";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { getSupabase, supabaseConfigured } from "@/lib/supabase";
import { parseOrder, type OrderItemRow, type OrderRow } from "@/lib/types";

interface Line extends OrderItemRow {
  model: string;
  name: string;
}

function parseLine(row: Record<string, unknown>): Line | null {
  if (
    typeof row["id"] !== "string" ||
    typeof row["order_id"] !== "string" ||
    typeof row["amount"] !== "number" ||
    typeof row["price"] !== "number"
  ) {
    return null;
  }
  const nested = row["products"];
  const prod =
    typeof nested === "object" && nested !== null
      ? (nested as Record<string, unknown>)
      : {};
  return {
    id: row["id"],
    order_id: row["order_id"],
    product_id:
      typeof row["product_id"] === "string" ? row["product_id"] : null,
    amount: row["amount"],
    price: row["price"],
    size: typeof row["size"] === "string" ? row["size"] : "",
    model: typeof prod["model"] === "string" ? prod["model"] : "",
    name: typeof prod["name"] === "string" ? prod["name"] : "",
  };
}

export default function OrderDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const { t } = useI18n();
  const { userId, loading: authLoading } = useAuth();
  const [order, setOrder] = useState<OrderRow | null>(null);
  const [lines, setLines] = useState<Line[]>([]);
  const [state, setState] = useState<"loading" | "ready" | "failed">("loading");
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState<Record<string, number>>({});
  const [removed, setRemoved] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchAll = useCallback(async () => {
    setState("loading");
    try {
      const sb = getSupabase();
      const { data: orow, error: oerr } = await sb
        .from("orders")
        .select("id, status, total, currency, created_at")
        .eq("id", id)
        .eq("is_deleted", false)
        .single();
      if (oerr) throw oerr;
      const parsed = parseOrder(orow as Record<string, unknown>);
      if (!parsed) throw new Error("bad order row");
      const { data: irows, error: ierr } = await sb
        .from("order_items")
        .select("id, amount, price, size, order_id, product_id, products(model, name)")
        .eq("order_id", id);
      if (ierr) throw ierr;
      setOrder(parsed);
      setLines(
        ((irows ?? []) as Record<string, unknown>[])
          .map(parseLine)
          .filter((l): l is Line => l !== null),
      );
      setEditing(false);
      setRemoved(new Set());
      setState("ready");
    } catch {
      setState("failed");
    }
  }, [id]);

  useEffect(() => {
    // Mount-time sync: order fetch must wait for the auth session.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (userId) void fetchAll();
  }, [userId, fetchAll]);

  const startEdit = () => {
    setDraft(Object.fromEntries(lines.map((l) => [l.id, l.amount])));
    setRemoved(new Set());
    setError(null);
    setEditing(true);
  };

  const save = async () => {
    if (!order || busy) return;
    setBusy(true);
    setError(null);
    try {
      const sb = getSupabase();
      await Promise.all([
        ...lines
          .filter((l) => !removed.has(l.id) && (draft[l.id] ?? l.amount) !== l.amount)
          .map((l) =>
            sb
              .from("order_items")
              .update({ amount: draft[l.id] ?? l.amount })
              .eq("id", l.id)
              .throwOnError(),
          ),
        ...[...removed].map((lineId) =>
          sb.from("order_items").delete().eq("id", lineId).throwOnError(),
        ),
      ]);
      await fetchAll();
    } catch {
      setError(t.unknownError);
    } finally {
      setBusy(false);
    }
  };

  const cancelOrder = async () => {
    if (!order || busy) return;
    setBusy(true);
    setError(null);
    try {
      await getSupabase()
        .from("orders")
        .update({ status: "cancelled" })
        .eq("id", order.id)
        .throwOnError();
      await fetchAll();
    } catch {
      setError(t.unknownError);
    } finally {
      setBusy(false);
    }
  };

  if (!supabaseConfigured()) return <p className="muted">{t.missingConfig}</p>;
  if (authLoading) return <p className="muted">{t.loading}</p>;
  if (!userId) {
    return (
      <div className="card flex flex-col gap-3 items-start">
        <p className="font-bold">{t.needSignIn}</p>
        <Link href={`/login?next=/orders/${id}`} className="btn btn-primary">
          {t.signIn}
        </Link>
      </div>
    );
  }
  if (state === "loading") return <p className="muted">{t.loading}</p>;
  if (state === "failed" || !order) {
    return (
      <div className="card flex flex-col gap-3 items-start">
        <p>{t.offline}</p>
        <button className="btn btn-primary" onClick={() => void fetchAll()}>
          {t.retry}
        </button>
      </div>
    );
  }

  const editable = order.status === "pending";
  const visible = lines.filter((l) => !removed.has(l.id));

  return (
    <div className="flex flex-col gap-4">
      <div className="card flex flex-col gap-2">
        <div className="flex items-center gap-2">
          <h1 className="font-bold text-xl">
            {t.orderDetail} #{order.id.slice(0, 8)}
          </h1>
          <span className="ms-auto">
            <StatusBadge status={order.status} />
          </span>
        </div>
        <div className="font-bold">
          {order.total > 0
            ? `${order.total} ${order.currency}`
            : t.totalPending}
        </div>
      </div>

      <div className="card flex flex-col gap-2">
        <div className="flex items-center gap-2">
          <h2 className="font-bold">
            {t.orderLines} · {visible.length}
          </h2>
          {editable && !editing ? (
            <button
              className="btn btn-ghost !px-3 !py-1 text-sm ms-auto"
              onClick={startEdit}
            >
              {t.editOrder}
            </button>
          ) : null}
        </div>
        {visible.map((l) => (
          <div key={l.id} className="flex items-center gap-2 text-sm">
            <span className="flex-1">
              {l.name || l.model}
              {l.size ? ` (${l.size})` : ""} ×{" "}
              {editing ? (draft[l.id] ?? l.amount) : l.amount}
            </span>
            {editing ? (
              <>
                <button
                  className="btn btn-ghost !px-2 !py-0.5"
                  onClick={() =>
                    setDraft((d) => ({
                      ...d,
                      [l.id]: Math.max(1, (d[l.id] ?? l.amount) - 1),
                    }))
                  }
                >
                  −
                </button>
                <button
                  className="btn btn-ghost !px-2 !py-0.5"
                  onClick={() =>
                    setDraft((d) => ({
                      ...d,
                      [l.id]: Math.min(999, (d[l.id] ?? l.amount) + 1),
                    }))
                  }
                >
                  +
                </button>
                <button
                  className="btn btn-ghost !px-2 !py-0.5"
                  onClick={() =>
                    setRemoved((s) => new Set(s).add(l.id))
                  }
                >
                  {t.remove}
                </button>
              </>
            ) : null}
          </div>
        ))}
        {editing ? (
          <div className="flex gap-2 mt-2">
            <button
              className="btn btn-primary flex-1"
              disabled={busy}
              onClick={() => void save()}
            >
              {busy ? t.saving : t.saveChanges}
            </button>
            <button
              className="btn btn-ghost"
              disabled={busy}
              onClick={() => setEditing(false)}
            >
              {t.doneEditing}
            </button>
          </div>
        ) : null}
        {error ? <p style={{ color: "#dc2626" }}>{error}</p> : null}
      </div>

      {editable && !editing ? (
        <button
          className="btn btn-ghost"
          disabled={busy}
          onClick={() => void cancelOrder()}
        >
          {busy ? t.cancelling : t.cancelOrder}
        </button>
      ) : null}
    </div>
  );
}
