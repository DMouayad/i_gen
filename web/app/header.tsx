"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";

export default function Header() {
  const { t, lang, toggle } = useI18n();
  const { userId, loading, signOut } = useAuth();
  const pathname = usePathname();
  const router = useRouter();

  const link = (href: string, label: string) => (
    <Link
      key={href}
      href={href}
      className={`px-3 py-2 rounded-lg font-semibold ${pathname === href ? "underline underline-offset-4" : ""
        }`}
    >
      {label}
    </Link>
  );

  return (
    <header className="border-b" style={{ borderColor: "var(--border)" }}>
      <div className="max-w-3xl mx-auto px-4 py-3 flex items-center gap-2">
        <Link href="/" className="flex items-center gap-1.5 me-2">
          <span
            className="text-xl sm:text-3xl"
            style={{
              color: "var(--accent)",
              fontFamily: "serif",
            }}
          >
            MED CORSET
          </span>
          <span className="muted text-xs hidden sm:inline">{t.appName}</span>
        </Link>
        <nav className="flex items-center gap-1">
          {link("/", t.catalog)}
          {userId ? link("/orders", `${t.orders}`) : null}
        </nav>
        <div className="ms-auto flex items-center gap-2">
          <button
            className="btn btn-ghost !px-3 !py-1.5 text-sm"
            onClick={toggle}
          >
            {lang === "en" ? "العربية" : "EN"}
          </button>
          {loading ? null : userId ? (
            <button
              className="btn btn-ghost !px-3 !py-1.5 text-sm"
              onClick={async () => {
                await signOut();
                router.push("/login");
              }}
            >
              {t.signOut}
            </button>
          ) : (
            <Link
              href="/login"
              className="btn btn-primary !px-3 !py-1.5 text-sm"
            >
              {t.signIn}
            </Link>
          )}
        </div>
      </div>
    </header>
  );
}
