// Phase 7 — invite-user Edge Function (admin-only, WhatsApp delivery).
//
// Deploy: supabase functions deploy invite-user
// Required secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Required env: INVITE_DOMAIN (e.g. invited.local), APP_CALLBACK
//   (e.g. io.invogen.app://invite-callback), WEB_WELCOME_URL
//   (e.g. https://orders.<domain>/welcome)
//
// Contract:
//   POST { name_ar, name_en, phone, role, mode? }
//     mode: "invite" (default) | "resend" | "recovery"
//   200 { fake_email, action_link, mode }
//   4xx { error } — human-readable, safe to show verbatim
//     ("already invited — use resend", "only admins may invite", ...)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.17.0";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

  const ROLES = new Set(["employee", "customer"]);
const INVITE_DOMAIN = Deno.env.get("INVITE_DOMAIN") ?? "invited.local";
const APP_CALLBACK = Deno.env.get("APP_CALLBACK") ?? "io.invogen.app://invite-callback";
const WEB_WELCOME_URL = Deno.env.get("WEB_WELCOME_URL") ?? "";

function slugName(nameEn: string): string {
  return nameEn
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, ".")
    .replace(/^\.+|\.+$/g, "")
    .slice(0, 32) || "user";
}

function fail(status: number, error: string): Response {
  return new Response(JSON.stringify({ error }), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return fail(405, "POST only.");

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !serviceKey) return fail(500, "Invite service is not configured.");

  // Caller must be an authenticated admin; the service key below is never
  // exposed — it only acts after this check passes. The JWT is passed
  // explicitly to getUser: global headers are not reliably forwarded to
  // the Auth server by the SDK, which silently authenticates nobody.
  const authHeader = req.headers.get("Authorization") ?? "";
  const callerJwt = authHeader.match(/^Bearer (.+)$/i)?.[1]?.trim() ?? "";
  if (!callerJwt) return fail(401, "Sign in first.");
  const callerClient = createClient(
    url,
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { auth: { persistSession: false } },
  );
  const { data: caller, error: callerError } = await callerClient.auth.getUser(
    callerJwt,
  );
  if (callerError || !caller?.user) {
    console.error(`invite-user: caller getUser failed: ${callerError?.message}`);
    return fail(401, "Sign in first.");
  }
  const callerRole =
    (caller.user.app_metadata as Record<string, unknown>)?.["role"]?.toString() ??
    (caller.user.user_metadata as Record<string, unknown>)?.["role"]?.toString();
  if (callerRole !== "admin") return fail(403, "Only admins may invite.");

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail(400, "Invalid request body.");
  }
  const nameAr = (body["name_ar"] ?? "").toString().trim();
  const nameEn = (body["name_en"] ?? "").toString().trim();
  const phone = (body["phone"] ?? "").toString().trim();
  const role = (body["role"] ?? "").toString().trim().toLowerCase();
  const mode = ((body["mode"] ?? "invite") as string).toLowerCase();
  if (!nameAr || !nameEn || !phone) return fail(400, "Arabic name, English name, and phone are required.");
  if (!ROLES.has(role)) return fail(400, "Role must be employee or customer.");
  if (!["invite", "resend", "recovery"].includes(mode)) return fail(400, "Unknown mode.");

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  // Duplicate phone ⇒ never duplicate: point at resend.
  const { data: existing } = await admin
    .from("profiles")
    .select("fake_email")
    .eq("phone", phone)
    .maybeSingle();

  // Resend/recovery for an unknown phone is a dead end — fail cleanly
  // instead of synthesizing a second identity for the same human.
  if (mode !== "invite" && !existing) {
    return fail(404, "No invite found for this phone — create a new invite.");
  }
  if (mode === "invite" && existing) {
    return fail(409, "This phone is already invited — use resend.");
  }

  // Resolve the login identity: reuse on resend/recovery, synthesize on invite.
  let fakeEmail = (existing?.fake_email as string | undefined) ?? "";
  if (mode === "invite" || !fakeEmail) {
    const base = slugName(nameEn);
    fakeEmail = `${base}@${INVITE_DOMAIN}`;
    for (let attempt = 0; attempt < 5; attempt++) {
      const candidate = attempt === 0
        ? fakeEmail
        : `${base}.${Math.floor(1000 + Math.random() * 9000)}@${INVITE_DOMAIN}`;
      const { data: clash } = await admin
        .from("profiles")
        .select("id")
        .eq("fake_email", candidate)
        .maybeSingle();
      if (!clash) {
        fakeEmail = candidate;
        break;
      }
    }
  }

  const redirectTo = role === "employee" ? APP_CALLBACK : WEB_WELCOME_URL;
  if (!redirectTo) return fail(500, "Invite destination is not configured.");

  // Native link generation — sends no email; the admin forwards via WhatsApp.
  // Invite mode is only valid for a brand-new login (the platform rejects
  // invites for existing users), so resend/recovery for a known identity
  // always use recovery mode: the user lands on password setup either way.
  const linkType = mode === "invite" && !existing ? "invite" : "recovery";
  const { data: linkData, error: linkError } = await admin.auth.admin.generateLink({
    type: linkType,
    email: fakeEmail,
    options: {
      redirectTo,
      data: { role, name_ar: nameAr, name_en: nameEn, phone },
    },
  } as never);
  if (linkError || !linkData) {
    return fail(502, `Could not create the invite link: ${linkError?.message ?? "unknown error"}`);
  }
  const actionLink =
    (linkData as Record<string, unknown>)["action_link"]?.toString() ??
    (linkData as Record<string, Record<string, unknown>>)?.["properties"]?.["action_link"]?.toString() ??
    "";
  if (!actionLink) return fail(502, "Invite link came back empty — try again.");

  const userId = (linkData as { user?: { id?: string } })?.user?.id;
  if (!userId) return fail(502, "Invite user was not created — try again.");

  // Profiles is the truth; token metadata is the fast RLS copy — one unit.
  const { error: profileError } = await admin.from("profiles").upsert(
    { id: userId, role, name_ar: nameAr, name_en: nameEn, phone, fake_email: fakeEmail },
    { onConflict: "id" },
  );
  if (profileError) {
    if (profileError.code === "23505") {
      return fail(409, "This phone is already invited — use resend.");
    }
    return fail(502, `Invite link created but profile save failed: ${profileError.message}`);
  }
  const { error: metaError } = await admin.auth.admin.updateUserById(userId, {
    app_metadata: { role },
    user_metadata: { role, name_ar: nameAr, name_en: nameEn, phone },
  });
  if (metaError) return fail(502, `Profile saved but role stamp failed: ${metaError.message}`);

  return new Response(JSON.stringify({ fake_email: fakeEmail, action_link: actionLink, mode }), {
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
