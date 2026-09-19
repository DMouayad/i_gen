// Shared date formatting for order screens (catalog-adjacent seam: both the
// orders list and the order detail render the same placed-on date).
export function fmtDate(iso: string | null, lang: string): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleDateString(lang === "ar" ? "ar" : "en", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}
