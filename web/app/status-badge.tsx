"use client";

import { useI18n } from "@/lib/i18n";

const known = new Set(["pending", "confirmed", "delivered", "cancelled"]);

export default function StatusBadge({ status }: { status: string }) {
  const { t } = useI18n();
  const label =
    status === "pending"
      ? t.statusPending
      : status === "confirmed"
        ? t.statusConfirmed
        : status === "delivered"
          ? t.statusDelivered
          : status === "cancelled"
            ? t.statusCancelled
            : status;
  return (
    <span className={`badge ${known.has(status) ? `badge-${status}` : ""}`}>
      {label}
    </span>
  );
}
