"use client";

import "./globals.css";

// Replaces the root layout when a client exception escapes: shows the real
// error (message + digest) instead of the generic "couldn't load" page, so a
// distributor can report exactly what broke. Static EN/AR copy — providers
// from the root layout are not mounted here.
export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html lang="en">
      <body className="min-h-screen antialiased">
        <main className="max-w-3xl mx-auto px-4 py-6">
          <div className="card flex flex-col gap-3 items-start">
            <h1 className="font-bold text-xl">
              Something broke · حدث خطأ
            </h1>
            <p className="text-sm break-all" dir="ltr">
              {error.message || "Unknown error"}
            </p>
            {error.digest ? (
              <p className="muted text-sm" dir="ltr">
                Code: {error.digest}
              </p>
            ) : null}
            <button className="btn btn-primary" onClick={() => reset()}>
              Reload · إعادة التحميل
            </button>
          </div>
        </main>
      </body>
    </html>
  );
}
