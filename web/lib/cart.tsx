"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import type { CartLine } from "./types";

const KEY = "dist-cart-v1";

interface Cart {
  lines: CartLine[];
  count: number;
  add: (line: Omit<CartLine, "qty">, qty: number) => void;
  setQty: (productId: string, size: string, qty: number) => void;
  remove: (productId: string, size: string) => void;
  clear: () => void;
}

const Ctx = createContext<Cart>({
  lines: [],
  count: 0,
  add: () => {},
  setQty: () => {},
  remove: () => {},
  clear: () => {},
});

function load(): CartLine[] {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (l): l is CartLine =>
        typeof l === "object" &&
        l !== null &&
        typeof (l as CartLine).productId === "string" &&
        typeof (l as CartLine).qty === "number" &&
        (l as CartLine).qty > 0,
    );
  } catch {
    return [];
  }
}

export function CartProvider({ children }: { children: ReactNode }) {
  const [lines, setLines] = useState<CartLine[]>([]);
  // Mount-time hydration from localStorage (SSR-unsafe to read during render).
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => setLines(load()), []);
  useEffect(() => {
    try {
      localStorage.setItem(KEY, JSON.stringify(lines));
    } catch {
      // Storage full/blocked — cart still works for this session.
    }
  }, [lines]);

  const add = useCallback((line: Omit<CartLine, "qty">, qty: number) => {
    if (qty <= 0) return;
    setLines((prev) => {
      const i = prev.findIndex(
        (l) => l.productId === line.productId && l.size === line.size,
      );
      if (i < 0) return [...prev, { ...line, qty }];
      const next = [...prev];
      next[i] = { ...next[i], qty: next[i].qty + qty };
      return next;
    });
  }, []);

  const setQty = useCallback(
    (productId: string, size: string, qty: number) => {
      setLines((prev) =>
        qty <= 0
          ? prev.filter(
              (l) => !(l.productId === productId && l.size === size),
            )
          : prev.map((l) =>
              l.productId === productId && l.size === size ? { ...l, qty } : l,
            ),
      );
    },
    [],
  );

  const remove = useCallback((productId: string, size: string) => {
    setLines((prev) =>
      prev.filter((l) => !(l.productId === productId && l.size === size)),
    );
  }, []);

  const clear = useCallback(() => setLines([]), []);

  const count = lines.reduce((n, l) => n + l.qty, 0);
  return (
    <Ctx.Provider value={{ lines, count, add, setQty, remove, clear }}>
      {children}
    </Ctx.Provider>
  );
}

export function useCart(): Cart {
  return useContext(Ctx);
}
