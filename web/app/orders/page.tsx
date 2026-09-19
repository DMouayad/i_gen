"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import StatusBadge from "@/app/status-badge";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { fmtDate } from "@/lib/format";
import { getSupabase, supabaseConfigured } from "@/lib/supabase";
import { parseOrder, type OrderRow } from "@/lib/types";

export default function OrdersPage() {
  const { t, lang } = useI18n();
  const { userId, loading: authLoading } = useAuth();
  const [orders, setOrders] = useState<OrderRow[]>([]);
  const [state, setState] = useState<"loading" | "ready" | "failed">("loading");

  const fetchOrders = useCallback(async () => {
    setState("loading");
    try {
      const { data, error } = await getSupabase()
        .from("orders")
        .select("id, status, total, currency, created_at")
        .eq("is_deleted", false)
        .order("created_at", { ascending: false })
        .limit(200);
      if (error) throw error;
      setOrders(
        ((data ?? []) as Record<string, unknown>[])
          .map(parseOrder)
          .filter((o): o is OrderRow => o !== null),
      );
      setState("ready");
    } catch {
      setState("failed");
    }
  }, []);

  useEffect(() => {
    // Mount-time sync: order history fetch must wait for the auth session.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (userId) void fetchOrders();
  }, [userId, fetchOrders]);

  if (!supabaseConfigured()) return <p className="muted">{t.missingConfig}</p>;
  if (authLoading) return <p className="muted">{t.loading}</p>;
  if (!userId) {
    return (
      <div className="card flex flex-col gap-3 items-start">
        <p className="font-bold">{t.needSignIn}</p>
        <Link href="/login?next=/orders" className="btn btn-primary">
          {t.signIn}
        </Link>
      </div>
    );
  }
  if (state === "loading") return <p className="muted">{t.loading}</p>;
  if (state === "failed") {
    return (
      <div className="card flex flex-col gap-3 items-start">
        <p>{t.offline}</p>
        <button className="btn btn-primary" onClick={() => void fetchOrders()}>
          {t.retry}
        </button>
      </div>
    );
  }
  if (orders.length === 0) return <p className="muted">{t.emptyOrders}</p>;

  return (
    <div className="flex flex-col gap-2">
      <h1 className="sr-only">{t.orders}</h1>
      {orders.map((o) => (
        <Link key={o.id} href={`/orders/${o.id}`} className="card">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="muted text-sm">
              {t.placedOn} {fmtDate(o.created_at, lang)}
            </span>
            <span className="ms-auto">
              <StatusBadge status={o.status} />
            </span>
          </div>
        </Link>
      ))}
    </div>
  );
}
