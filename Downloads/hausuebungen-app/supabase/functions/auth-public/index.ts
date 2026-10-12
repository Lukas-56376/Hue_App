import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

const ADMINS = ["daweed@lukio.site", "nico@lukio.site"];
const isAdminEmail = (e: string) => ADMINS.includes((e || "").toLowerCase());
const ADMIN = ADMINS[0];
const DOMAIN = "lukio.site";

const url = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(url, serviceKey);

function json(data: unknown, status = 200) {
  return Response.json(data, { status, headers: cors });
}

function normName(raw: string) {
  return String(raw || "").trim().toLowerCase().replace(/@.*$/, "");
}

function randomCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

async function notifyAdmin(title: string, body: string, tag: string) {
  try {
    const vapidPublic = Deno.env.get("VAPID_PUBLIC_KEY");
    const vapidPrivate = Deno.env.get("VAPID_PRIVATE_KEY");
    const vapidSubject = Deno.env.get("VAPID_SUBJECT") || `mailto:${ADMIN}`;
    if (!vapidPublic || !vapidPrivate) return { sent: 0 };

    webpush.setVapidDetails(vapidSubject, vapidPublic, vapidPrivate);

    const { data: users } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
    const adminUsers = (users?.users || []).filter(u => isAdminEmail(u.email || ""));
    if (!adminUsers.length) return { sent: 0 };

    const adminIds = adminUsers.map(u => u.id);
    const { data: subs } = await admin
      .from("push_subscriptions")
      .select("id,endpoint,subscription")
      .in("user_id", adminIds);

    let sent = 0;
    for (const s of subs || []) {
      try {
        await webpush.sendNotification(
          s.subscription,
          JSON.stringify({ title, body, tag })
        );
        sent++;
      } catch (e: unknown) {
        const status = (e as { statusCode?: number })?.statusCode;
        if (status === 404 || status === 410) {
          await admin.from("push_subscriptions").delete().eq("id", s.id);
        }
      }
    }
    return { sent };
  } catch {
    return { sent: 0 };
  }
}

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json().catch(() => ({}));
    const action = String(body.action || "");

    if (action === "register") {
      const name = normName(body.username);
      const password = String(body.password || "");
      const password2 = String(body.password2 || body.passwordConfirm || "");
      if (!/^[a-z0-9._-]{2,32}$/.test(name)) {
        return json({ error: "Benutzername: 2–32 Zeichen, nur a–z, 0–9, Punkt, _ oder -." }, 400);
      }
      if (password.length < 6) return json({ error: "Passwort mindestens 6 Zeichen." }, 400);
      if (password !== password2) return json({ error: "Passwörter stimmen nicht überein." }, 400);
      if (name === "admin" || `${name}@${DOMAIN}` === ADMIN) {
        return json({ error: "Dieser Name ist reserviert." }, 400);
      }
      const email = `${name}@${DOMAIN}`;
      const { data, error } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true
      });
      if (error) {
        const msg = (error.message || "").toLowerCase();
        if (msg.includes("already") || msg.includes("registered") || msg.includes("exists")) {
          return json({ error: "Benutzername ist schon vergeben." }, 409);
        }
        throw error;
      }
      await notifyAdmin(
        "Neuer Account",
        `${name} hat sich registriert.`,
        "user-register"
      );
      return json({ ok: true, email: data.user?.email, name });
    }

    if (action === "request_reset") {
      const name = normName(body.username);
      if (!name) return json({ error: "Benutzername eingeben." }, 400);
      const email = `${name}@${DOMAIN}`;

      // Immer gleiche Antwort (kein User-Enumeration)
      const generic = { ok: true, message: "Wenn der Account existiert, hat der Admin einen Code bekommen." };

      const { data: listed } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
      const target = (listed?.users || []).find(u => (u.email || "").toLowerCase() === email);
      if (!target) return json(generic);

      const code = randomCode();
      const expires = new Date(Date.now() + 30 * 60 * 1000).toISOString();

      await admin.from("password_resets").delete().eq("email", email);
      const { error: insErr } = await admin.from("password_resets").insert({
        email,
        code,
        expires_at: expires,
        used: false
      });
      if (insErr) throw insErr;

      const push = await notifyAdmin(
        "Passwort-Reset-Code",
        `${name}: Code ${code} (30 Min gültig)`,
        "password-reset"
      );

      // Admin-Panel-Hinweis
      try {
        await admin.from("activity_logs").insert({
          user_id: target.id,
          user_email: email,
          action: "password_reset_requested",
          detail: `Code an Admin gesendet (Push: ${push.sent})`
        });
      } catch { /* ignore */ }

      return json(generic);
    }

    if (action === "confirm_reset") {
      const name = normName(body.username);
      const code = String(body.code || "").trim();
      const password = String(body.password || "");
      const password2 = String(body.password2 || body.passwordConfirm || "");
      if (!name || !code) return json({ error: "Benutzername und Code nötig." }, 400);
      if (password.length < 6) return json({ error: "Passwort mindestens 6 Zeichen." }, 400);
      if (password !== password2) return json({ error: "Passwörter stimmen nicht überein." }, 400);

      const email = `${name}@${DOMAIN}`;
      const { data: rows, error } = await admin
        .from("password_resets")
        .select("*")
        .eq("email", email)
        .eq("code", code)
        .eq("used", false)
        .order("created_at", { ascending: false })
        .limit(1);
      if (error) throw error;
      const row = rows?.[0];
      if (!row) return json({ error: "Code ungültig oder schon benutzt." }, 400);
      if (new Date(row.expires_at).getTime() < Date.now()) {
        return json({ error: "Code abgelaufen. Neu anfordern." }, 400);
      }

      const { data: listed } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
      const target = (listed?.users || []).find(u => (u.email || "").toLowerCase() === email);
      if (!target) return json({ error: "Benutzer nicht gefunden." }, 404);

      const { error: upErr } = await admin.auth.admin.updateUserById(target.id, { password });
      if (upErr) throw upErr;

      await admin.from("password_resets").update({ used: true }).eq("id", row.id);
      return json({ ok: true });
    }

    if (action === "list_pending_resets") {
      // nur Admin mit JWT
      const auth = req.headers.get("Authorization");
      if (!auth) return json({ error: "Unauthorized" }, 401);
      const token = auth.replace(/^Bearer\s+/i, "");
      const { data: { user }, error: userError } = await admin.auth.getUser(token);
      if (userError || !user || !isAdminEmail(user.email || "")) {
        return json({ error: "Forbidden" }, 403);
      }
      const { data, error } = await admin
        .from("password_resets")
        .select("email,code,expires_at,used,created_at")
        .eq("used", false)
        .gt("expires_at", new Date().toISOString())
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      return json({ resets: data || [] });
    }

    return json({ error: "Unbekannte Aktion." }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
