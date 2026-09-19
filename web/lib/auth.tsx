"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { getSupabase, supabaseConfigured } from "./supabase";

export class NoAccountError extends Error {}
export class NotCustomerError extends Error {}

interface AuthState {
  userId: string | null;
  role: string | null;
  loading: boolean;
  signInWithPhone: (phone: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const Ctx = createContext<AuthState>({
  userId: null,
  role: null,
  loading: true,
  signInWithPhone: async () => {},
  signOut: async () => {},
});

function roleOf(user: unknown): string | null {
  if (typeof user !== "object" || user === null) return null;
  const meta = (user as { app_metadata?: unknown }).app_metadata;
  if (typeof meta !== "object" || meta === null) return null;
  const role = (meta as { role?: unknown }).role;
  return typeof role === "string" ? role : null;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [userId, setUserId] = useState<string | null>(null);
  const [role, setRole] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabaseConfigured()) {
      // Mount-time sync: session read must run after mount, not render.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setLoading(false);
      return;
    }
    const sb = getSupabase();
    sb.auth.getSession().then(({ data }) => {
      const u = data.session?.user ?? null;
      setUserId(u?.id ?? null);
      setRole(roleOf(u));
      setLoading(false);
    });
    const { data: sub } = sb.auth.onAuthStateChange((_event, session) => {
      const u = session?.user ?? null;
      setUserId(u?.id ?? null);
      setRole(roleOf(u));
      setLoading(false);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  const signInWithPhone = useCallback(async (phone: string, password: string) => {
    const sb = getSupabase();
    // Phone is the human key; the login identity is the synthesized email.
    const { data: email, error: rpcError } = await sb.rpc("phone_to_email", {
      p_phone: phone.trim(),
    });
    if (rpcError) throw rpcError;
    if (typeof email !== "string" || email.length === 0) {
      throw new NoAccountError(phone);
    }
    const { data, error } = await sb.auth.signInWithPassword({
      email,
      password,
    });
    if (error) throw error;
    const r = roleOf(data.user);
    if (r !== null && r !== "customer") {
      await sb.auth.signOut();
      throw new NotCustomerError(r);
    }
  }, []);

  const signOut = useCallback(async () => {
    if (supabaseConfigured()) await getSupabase().auth.signOut();
  }, []);

  return (
    <Ctx.Provider value={{ userId, role, loading, signInWithPhone, signOut }}>
      {children}
    </Ctx.Provider>
  );
}

export function useAuth(): AuthState {
  return useContext(Ctx);
}
