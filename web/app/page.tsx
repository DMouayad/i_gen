"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useAuth } from "@/lib/auth";
import { useCart } from "@/lib/cart";
import { useI18n } from "@/lib/i18n";
import { getSupabase, supabaseConfigured } from "@/lib/supabase";
import { parseProduct, type Product } from "@/lib/types";

type FetchState = "loading" | "ready" | "offline" | "error";

function ProductCard({ product }: { product: Product }) {
  const { t } = useI18n();
  const cart = useCart();
  const lines = cart.lines.filter((l) => l.productId === product.id);
  const qtyOf = (size: string) =>
    lines.find((l) => l.size === size)?.qty ?? 0;
  const total = lines.reduce((n, l) => n + l.qty, 0);
  const selected = total > 0;
  const addLine = (size: string, qty: number) =>
    cart.add(
      {
        productId: product.id,
        model: product.model,
        name: product.name,
        size,
      },
      qty,
    );
  // Products without sizes: no size row at all — the header itself is the
  // tap target (+1), with qty pill + corner minus once selected.
  if (product.sizes.length === 0) {
    return (
      <div className={selected ? "card card-on relative" : "card relative"}>
        <button
          type="button"
          aria-label={`${product.model} ${product.name}: ${total}`}
          onClick={() => addLine("", 1)}
          className="sizeless-hit"
        >
          <span className="text-[15px] font-semibold">{product.model}</span>
          <span className=" text-sm truncate">{product.name}</span>
          {selected ? <span className="badge">× {total}</span> : null}
        </button>
        {selected ? (
        <button
          type="button"
          aria-label={`${t.decrease}: ${product.model} ${product.name}`}
          onClick={() => cart.setQty(product.id, "", total - 1)}
          className="size-dec"
        >
          −
        </button>
        ) : null}
      </div>
    );
  }
  return (
    <div className="card flex flex-col gap-2">
      <div className="flex items-baseline gap-2">
        <span className="text-[15px] font-semibold">{product.model}</span>
        <span className="text-sm truncate">{product.name}</span>
      </div>
      <div className="flex flex-wrap gap-2">
        {product.sizes.map((size) => {
          const qty = qtyOf(size);
          const on = qty > 0;
          return (
            <div key={size} className="relative">
              <button
                type="button"
                aria-label={`${size}: ${qty}`}
                onClick={() => addLine(size, 1)}
                className={on ? "size-card size-card-on" : "size-card"}
              >
                <span className="size-label">{size}</span>
                <span className="size-qty">{qty}</span>
              </button>
              {on ? (
              <button
                type="button"
                aria-label={`${t.decrease}: ${size} · ${product.model}`}
                onClick={() => cart.setQty(product.id, size, qty - 1)}
                className="size-dec"
              >
                −
              </button>
              ) : null}
            </div>
          );
        })}
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
  const [previewOpen, setPreviewOpen] = useState(false);
  const fabRef = useRef<HTMLButtonElement>(null);
  const dialogRef = useRef<HTMLDivElement>(null);

  // Modal behavior: focus in on open, Escape closes, Tab wraps inside,
  // focus returns to the FAB on close.
  useEffect(() => {
    if (!previewOpen) return;
    const trigger = fabRef.current;
    dialogRef.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setPreviewOpen(false);
        return;
      }
      if (e.key !== "Tab" || !dialogRef.current) return;
      const items = [...dialogRef.current.querySelectorAll<HTMLElement>(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
      )].filter((el) => !el.hasAttribute("disabled"));
      if (items.length === 0) return;
      const first = items[0];
      const last = items[items.length - 1];
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
      trigger?.focus();
    };
  }, [previewOpen]);

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
        .insert({ customer_id: userId })
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
      setPreviewOpen(false);
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
      <h1 className="sr-only">{t.catalog}</h1>
      <input
        className="input"
        aria-label={t.search}
        placeholder={t.search}
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />
      {filtered.length === 0 ? (
        <p className="muted">{t.noProducts}</p>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          {filtered.map((p) => (
            <ProductCard key={p.id} product={p} />
          ))}
        </div>
      )}
      {cart.lines.length > 0 ? (
        <button
          ref={fabRef}
          type="button"
          className="fab"
          onClick={() => {
            setSubmitError(null);
            setPreviewOpen(true);
          }}
        >
          {t.previewOrder} · {cart.count}
        </button>
      ) : null}
      {previewOpen && cart.lines.length > 0 ? (
        <div
          className="dialog-backdrop"
          role="dialog"
          aria-modal="true"
          aria-label={t.previewOrder}
          onClick={() => setPreviewOpen(false)}
        >
          <div
            ref={dialogRef}
            tabIndex={-1}
            className="card dialog flex flex-col gap-3"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="font-bold text-lg">
              {t.previewOrder} · {cart.count}
            </div>
            <div className="table-scroll">
            <table className="order-table">
              <thead>
                <tr>
                  <th>{t.item}</th>
                  <th>{t.sizes}</th>
                  <th>{t.qty}</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {cart.lines.map((l) => (
                  <tr key={`${l.productId}|${l.size}`}>
                    <td>
                      <div className="font-semibold">{l.model}</div>
                      <div className="muted text-sm">{l.name}</div>
                    </td>
                    <td>{l.size === "" ? "—" : l.size}</td>
                    <td className="font-bold">× {l.qty}</td>
                    <td>
                      <button
                        className="btn btn-ghost !px-2 !py-0.5"
                        onClick={() => cart.remove(l.productId, l.size)}
                      >
                        {t.remove}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            </div>
            {submitError ? <p className="error">{submitError}</p> : null}
            <div className="flex gap-2">
              <button
                className="btn btn-ghost flex-1 !py-3"
                onClick={() => setPreviewOpen(false)}
              >
                {t.close}
              </button>
              <button
                className="btn btn-primary flex-1 !py-3 text-base"
                disabled={submitting}
                onClick={() => void submit()}
              >
                {submitting ? t.submitting : t.submitOrder}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
