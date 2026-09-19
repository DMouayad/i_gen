"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";
import { NoAccountError, NotCustomerError, useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { supabaseConfigured } from "@/lib/supabase";

function LoginForm() {
  const { t } = useI18n();
  const { signInWithPhone, userId, loading } = useAuth();
  const router = useRouter();
  const next = useSearchParams().get("next") ?? "/";
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!supabaseConfigured()) return <p className="muted">{t.missingConfig}</p>;
  if (!loading && userId) {
    router.replace(next);
    return <p className="muted">{t.loading}</p>;
  }

  const submit = async () => {
    if (busy || phone.trim().length === 0 || password.length === 0) return;
    setBusy(true);
    setError(null);
    try {
      await signInWithPhone(phone, password);
      router.replace(next);
    } catch (e) {
      if (e instanceof NoAccountError) setError(t.noAccount);
      else if (e instanceof NotCustomerError) setError(t.notCustomer);
      else if (
        e instanceof Error &&
        /invalid login|invalid.*password/i.test(e.message)
      ) {
        setError(t.wrongPassword);
      } else {
        setError(t.unknownError);
      }
      setBusy(false);
    }
  };

  return (
    <div className="card flex flex-col gap-3 max-w-md">
      <h1 className="font-bold text-xl">{t.signIn}</h1>
      <label className="flex flex-col gap-1 text-sm">
        {t.phone}
        <input
          className="input"
          dir="ltr"
          inputMode="tel"
          autoComplete="tel"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        {t.password}
        <input
          className="input"
          type="password"
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") void submit();
          }}
        />
      </label>
      {error ? <p className="error">{error}</p> : null}
      <button className="btn btn-primary" disabled={busy} onClick={() => void submit()}>
        {t.signIn}
      </button>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}
