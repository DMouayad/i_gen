import type { Metadata } from "next";
import { Readex_Pro } from "next/font/google";
import "./globals.css";
import { AuthProvider } from "@/lib/auth";
import { CartProvider } from "@/lib/cart";
import { I18nProvider } from "@/lib/i18n";
import Header from "./header";

// Shared type language with the mobile app (design/design-tokens.json).
const readex = Readex_Pro({
  subsets: ["latin", "arabic"],
  variable: "--font-sans",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Medcorset Wholesale Orders",
  description: "Place and follow orders",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={readex.variable}>
      <body className="min-h-screen flex flex-col antialiased">
        <I18nProvider>
          <AuthProvider>
            <CartProvider>
              <Header />
              <main className="flex-1 w-full max-w-3xl mx-auto px-4 py-6">
                {children}
              </main>
            </CartProvider>
          </AuthProvider>
        </I18nProvider>
      </body>
    </html>
  );
}
