"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useAuth } from "@/lib/auth";
import { useCart } from "@/lib/cart";
import { useI18n } from "@/lib/i18n";
import { getSupabase, supabaseConfigured } from "@/lib/supabase";
import { parseProduct, type Product } from "@/lib/types";

type FetchState = "loading" | "ready" | "offline" | "error";

function ProductCard({
  product,
  onAdd,
}: {
  product: Product;
  onAdd: (size: string, qty: number) => void;
}) {
  const { t } = useI18n();
  const [size, setSize] = useState(product.sizes[0] ?? "");
  const [qty, setQty] = useState(1);
  return (
    <div className="card flex flex-col gap-2">
      <div>
        <div className="font-bold">{product.name}</div>
        <div className="muted text-sm">{product.model}</div>
      </div>
      {product.sizes.length > 0 ? (
        <label className="flex items-center gap-2 text-sm">
          <span className="muted">{t.sizes}</span>
          <select
            className="input !w-auto"
            value={size}
            onChange={(e) => setSize(e.target.value)}
          >
            {product.sizes.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </label>
      ) : (
        <div className="muted text-sm">{t.sizeless}</div>
      )}
      <div className="flex items-center gap-2 mt-auto">
        <button
          className="btn btn-ghost !px-2 !py-1"
          onClick={() => setQty((q) => Math.max(1, q - 1))}
          aria-label="-"
        >
          −
        </button>
        <span className="w-8 text-center font-bold">{qty}</span>
        <button
          className="btn btn-ghost !px-2 !py-1"
          onClick={() => setQty((q) => Math.min(999, q + 1))}
          aria-label="+"
        >
          +
        </button>
        <button
          className="btn btn-primary !py-1 ms-auto"
          onClick={() => onAdd(size, qty)}
        >
          {t.add}
        </button>
      </div>
    </div>
  );
}

export default function CatalogPage() {
  const { t } = useI18n();
  const { userId, loading: authLoading } = useAuth();
  const cart = useCart();
  const router = useRouter();
  const [products, setProducts] = useState<Product[]>([]);
  const [state, setState] = useState<FetchState>("loading");
  const [query, setQuery] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  const fetchProducts = useCallback(async () => {
    setState("loading");
    try {
      const { data, error } = await getSupabase()
        .from("products")
        .select("id, model, name, sizes")
        .eq("is_deleted", false)
        .order("name")
        .limit(500);
      if (error) throw error;
      const rows = (data ?? []) as Record<string, unknown>[];
      setProducts(
        rows
          .map(parseProduct)
          .filter((p): p is Product => p !== null),
      );
      setState("ready");
    } catch (e) {
      setState(
        e instanceof TypeError || /network|fetch|failed/i.test(String(e))
          ? "offline"
          : "error",
      );
    }
  }, []);

  useEffect(() => {
    // Mount-time sync: catalog fetch must wait for the auth session.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (userId) void fetchProducts();
  }, [userId, fetchProducts]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return products;
    return products.filter(
      (p) =>
        p.name.toLowerCase().includes(q) || p.model.toLowerCase().includes(q),
    );
  }, [products, query]);

  const submit = useCallback(async () => {
    if (!userId || cart.lines.length === 0 || submitting) return;
    setSubmitting(true);
    setSubmitError(null);
    try {
      const sb = getSupabase();
      const { data: order, error: orderError } = await sb
        .from("orders")
        .insert({ distributor_id: userId })
        .select("id")
        .single();
      if (orderError) throw orderError;
      const orderId = (order as { id: string }).id;
      const { error: itemsError } = await sb.from("order_items").insert(
        cart.lines.map((l) => ({
          order_id: orderId,
          product_id: l.productId,
          amount: l.qty,
          price: 0,
          size: l.size,
        })),
      );
      if (itemsError) throw itemsError;
      cart.clear();
      router.push(`/orders/${orderId}`);
    } catch {
      setSubmitError(t.unknownError);
      setSubmitting(false);
    }
  }, [userId, cart, submitting, router, t]);

  if (!supabaseConfigured()) return <p className="muted">{t.missingConfig}</p>;
  if (authLoading) return <p className="muted">{t.loading}</p>;
  if (!userId) {
    return (
      <div className="card flex flex-col gap-3 items-start">
        <p className="font-bold">{t.needSignIn}</p>
        <p className="muted">{t.signInCta}</p>
        <Link href="/login" className="btn btn-primary">
          {t.signIn}
        </Link>
      </div>
    );
  }
  if (state === "loading") return <p className="muted">{t.loading}</p>;
  if (state !== "ready") {
    return (
      <div className="card flex flex-col gap-3 items-start">
        <p>{state === "offline" ? t.offline : t.unknownError}</p>
        <button className="btn btn-primary" onClick={() => void fetchProducts()}>
          {t.retry}
        </button>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <input
        className="input"
        placeholder={t.search}
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />
      {filtered.length === 0 ? (
        <p className="muted">{t.noProducts}</p>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          {filtered.map((p) => (
            <ProductCard
              key={p.id}
              product={p}
              onAdd={(size, qty) =>
                cart.add(
                  {
                    productId: p.id,
                    model: p.model,
                    name: p.name,
                    size,
                  },
                  qty,
                )
              }
            />
          ))}
        </div>
      )}
      {cart.lines.length > 0 ? (
        <div className="card flex flex-col gap-2 sticky bottom-4">
          <div className="font-bold">
            {t.cart} · {cart.count}
          </div>
          {cart.lines.map((l) => (
            <div
              key={`${l.productId}|${l.size}`}
              className="flex items-center gap-2 text-sm"
            >
              <span className="flex-1">
                {l.name}
                {l.size ? ` (${l.size})` : ""} × {l.qty}
              </span>
              <button
                className="btn btn-ghost !px-2 !py-0.5"
                onClick={() =>
                  cart.setQty(l.productId, l.size, l.qty - 1)
                }
              >
                −
              </button>
              <button
                className="btn btn-ghost !px-2 !py-0.5"
                onClick={() => cart.remove(l.productId, l.size)}
              >
                {t.remove}
              </button>
            </div>
          ))}
          {submitError ? <p style={{ color: "#dc2626" }}>{submitError}</p> : null}
          <button
            className="btn btn-primary"
            disabled={submitting}
            onClick={() => void submit()}
          >
            {submitting ? t.submitting : t.submitOrder}
          </button>
        </div>
      ) : null}
    </div>
  );
}
