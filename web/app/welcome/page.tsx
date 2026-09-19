"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { getSupabase, supabaseConfigured } from "@/lib/supabase";

// Customer landing for invite + recovery links (WEB_WELCOME_URL).
// The link carries ?code=… → exchange for a session → set own password.
// No secret ever travels in chat history (Phase 7).
function WelcomeForm() {
  const { t } = useI18n();
  const router = useRouter();
  const code = useSearchParams().get("code");
  const [phase, setPhase] = useState<"exchanging" | "ready" | "expired">(
    "exchanging",
  );
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!supabaseConfigured()) {
      // Mount-time sync: invite-code validity resolves after mount.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setPhase("expired");
      return;
    }
    void (async () => {
      const sb = getSupabase();
      // PKCE link (?code=…): redeem explicitly. A redeemed/expired code is
      // not fatal — the same human may already hold a session from another
      // tab, so fall through to the session check below.
      if (code) {
        const { error } = await sb.auth.exchangeCodeForSession(code);
        if (!error) {
          setPhase("ready");
          return;
        }
      } else if (
        typeof window !== "undefined" &&
        window.location.hash.includes("access_token")
      ) {
        // Implicit link (#access_token=…): the client auto-detects it on
        // init; allow a beat for the session to land before checking.
        await new Promise((r) => setTimeout(r, 800));
      }
      const { data } = await sb.auth.getSession();
      setPhase(data.session ? "ready" : "expired");
    })();
  }, [code]);

  if (!supabaseConfigured()) return <p className="muted">{t.missingConfig}</p>;
  if (phase === "exchanging") return <p className="muted">{t.loading}</p>;
  if (phase === "expired") {
    return (
      <div className="card flex flex-col gap-3 max-w-md">
        <h1 className="font-bold text-xl">{t.welcome}</h1>
        <p>{t.linkExpired}</p>
      </div>
    );
  }

  const save = async () => {
    if (busy || password.length < 6) return;
    setBusy(true);
    setError(null);
    const { error } = await getSupabase().auth.updateUser({ password });
    if (error) {
      setError(t.unknownError);
      setBusy(false);
      return;
    }
    router.replace("/");
  };

  return (
    <div className="card flex flex-col gap-3 max-w-md">
      <h1 className="font-bold text-xl">{t.welcome}</h1>
      <p className="muted text-sm">{t.welcomeBody}</p>
      <label className="flex flex-col gap-1 text-sm">
        {t.newPassword}
        <input
          className="input"
          type="password"
          autoComplete="new-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") void save();
          }}
        />
      </label>
      {error ? <p className="error">{error}</p> : null}
      <button
        className="btn btn-primary"
        disabled={busy || password.length < 6}
        onClick={() => void save()}
      >
        {t.setPassword}
      </button>
    </div>
  );
}

export default function WelcomePage() {
  return (
    <Suspense>
      <WelcomeForm />
    </Suspense>
  );
}
