import type { Metadata } from "next";
import "./globals.css";
import { AuthProvider } from "@/lib/auth";
import { CartProvider } from "@/lib/cart";
import { I18nProvider } from "@/lib/i18n";
import Header from "./header";

export const metadata: Metadata = {
  title: "Distributor Orders",
  description: "Place and follow orders",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
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
