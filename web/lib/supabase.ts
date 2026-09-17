import { createClient, type SupabaseClient } from "@supabase/supabase-js";

// Browser-only client (localStorage session, auto-refresh). All web reads
// and writes are live server calls — no offline cache, matching the
// Flutter app's online-first orders seam (Phase 10).
let browser: SupabaseClient | null = null;

export function supabaseConfigured(): boolean {
  return Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL &&
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  );
}

export function getSupabase(): SupabaseClient {
  if (!browser) {
    browser = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "",
    );
  }
  return browser;
}
