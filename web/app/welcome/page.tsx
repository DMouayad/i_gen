"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { getSupabase, supabaseConfigured } from "@/lib/supabase";

// Distributor landing for invite + recovery links (WEB_WELCOME_URL).
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
    if (!supabaseConfigured() || !code) {
      // Mount-time sync: invite-code validity resolves after mount.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setPhase("expired");
      return;
    }
    getSupabase()
      .auth.exchangeCodeForSession(code)
      .then(({ error }) => setPhase(error ? "expired" : "ready"));
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
      {error ? <p style={{ color: "#dc2626" }}>{error}</p> : null}
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
