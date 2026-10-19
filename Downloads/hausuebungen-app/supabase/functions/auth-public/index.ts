import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-forwarded-for, cf-connecting-ip, x-real-ip",
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


function clientIp(req: Request, body: Record<string, unknown> = {}) {
  const h = req.headers;
  const raw =
    h.get("cf-connecting-ip") ||
    h.get("x-real-ip") ||
    (h.get("x-forwarded-for") || "").split(",")[0].trim() ||
    String(body.client_ip || body.ip || "") ||
    "";
  return raw.slice(0, 80);
}

async function assertNotBanned(ip: string) {
  if (!ip) return;
  const { data } = await admin.from("ip_bans").select("id,reason").eq("ip", ip).eq("active", true).limit(1);
  if (data?.length) {
    const err = new Error("IP gesperrt" + (data[0].reason ? ": " + data[0].reason : ""));
    (err as Error & { status?: number }).status = 403;
    throw err;
  }
}

async function logIp(opts: {
  ip: string; action: string; user_id?: string | null; user_email?: string | null;
  user_agent?: string | null; detail?: string | null;
}) {
  try {
    if (!opts.ip) return;
    await admin.from("ip_logs").insert({
      ip: opts.ip,
      action: opts.action,
      user_id: opts.user_id || null,
      user_email: opts.user_email || null,
      user_agent: (opts.user_agent || "").slice(0, 400),
      detail: opts.detail || null
    });
  } catch { /* ignore log errors */ }
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
      const ip = clientIp(req, body);
      await assertNotBanned(ip);
      const name = normName(body.username);
      const password = String(body.password || "");
      const password2 = String(body.password2 || body.passwordConfirm || "");
      if (!/^[a-z0-9._-]{2,32}$/.test(name)) {
        return json({ error: "Benutzername: 2–32 Zeichen, nur a–z, 0–9, Punkt, _ oder -." }, 400);
      }
      if (password.length < 6) return json({ error: "Passwort mindestens 6 Zeichen." }, 400);
      if (password !== password2) return json({ error: "Passwörter stimmen nicht überein." }, 400);
      if (name === "admin" || isAdminEmail(`${name}@${DOMAIN}`)) {
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
      // Schreibrecht (Trigger macht das auch; hier explizit)
      if (data.user?.id) {
        await admin.from("klassen_hu_permissions").upsert({
          user_id: data.user.id,
          user_email: email,
          can_write: true
        }, { onConflict: "user_id" });
      }
      await logIp({
        ip, action: "register", user_id: data.user?.id, user_email: email,
        user_agent: req.headers.get("user-agent"), detail: "self-register"
      });
      await notifyAdmin(
        "Neuer Account",
        `${name} hat sich registriert (${ip || "IP?"}).`,
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

    
    
    if (action === "check_login_rate") {
      const ip = clientIp(req, body);
      const windowMs = 10 * 60 * 1000;
      const since = new Date(Date.now() - windowMs).toISOString();
      let count = 0;
      if (ip) {
        const { data } = await admin.from("ip_logs")
          .select("id, created_at")
          .eq("ip", ip)
          .eq("action", "login_failed")
          .gte("created_at", since);
        count = (data || []).length;
      }
      const limit = 5;
      const blocked = count >= limit;
      return json({ ok: true, count, limit, blocked, window_minutes: 10, ip: ip || null });
    }

    if (action === "log_session") {
      const ip = clientIp(req, body);
      await assertNotBanned(ip);
      const auth = req.headers.get("Authorization");
      let user_id: string | null = null;
      let user_email: string | null = null;
      if (auth) {
        const token = auth.replace(/^Bearer\s+/i, "");
        const { data: { user } } = await admin.auth.getUser(token);
        user_id = user?.id || null;
        user_email = user?.email || null;
      }
      if (!user_id && body.user_email) user_email = String(body.user_email);
      await logIp({
        ip,
        action: String(body.event || "login"),
        user_id,
        user_email,
        user_agent: req.headers.get("user-agent") || String(body.user_agent || ""),
        detail: String(body.detail || "session")
      });
      return json({ ok: true, ip: ip || null });
    }

    if (action === "check_ban") {
      const ip = clientIp(req, body);
      const banned = ip ? await admin.from("ip_bans").select("reason").eq("ip", ip).eq("active", true).maybeSingle() : { data: null };
      return json({ banned: !!banned.data, reason: banned.data?.reason || null, ip: ip || null });
    }

    if (action === "list_ip_logs" || action === "list_ip_bans" || action === "ban_ip" || action === "unban_ip" || action === "list_devices") {
      const auth = req.headers.get("Authorization");
      if (!auth) return json({ error: "Unauthorized" }, 401);
      const token = auth.replace(/^Bearer\s+/i, "");
      const { data: { user }, error: userError } = await admin.auth.getUser(token);
      if (userError || !user || !isAdminEmail(user.email || "")) return json({ error: "Forbidden" }, 403);

      if (action === "list_ip_logs") {
        const { data, error } = await admin.from("ip_logs").select("*").order("created_at", { ascending: false }).limit(100);
        if (error) throw error;
        return json({ logs: data || [] });
      }
      if (action === "list_ip_bans") {
        const { data, error } = await admin.from("ip_bans").select("*").order("created_at", { ascending: false }).limit(100);
        if (error) throw error;
        return json({ bans: data || [] });
      }
      if (action === "list_devices") {
        const { data: logs, error } = await admin.from("ip_logs").select("ip,user_email,created_at,action").order("created_at", { ascending: false }).limit(400);
        if (error) throw error;
        const { data: bans } = await admin.from("ip_bans").select("ip").eq("active", true);
        const banned = new Set((bans || []).map((b: { ip: string }) => b.ip));
        const map = new Map<string, { ip: string; user_email: string | null; last_seen: string; banned: boolean }>();
        for (const row of logs || []) {
          const ip = String(row.ip || "").trim();
          if (!ip) continue;
          if (map.has(ip)) continue;
          map.set(ip, {
            ip,
            user_email: row.user_email || null,
            last_seen: row.created_at,
            banned: banned.has(ip)
          });
        }
        return json({ devices: [...map.values()] });
      }
      if (action === "ban_ip") {
        const ip = String(body.ip || "").trim();
        if (!ip) return json({ error: "IP fehlt." }, 400);
        const reason = String(body.reason || "");
        const { error } = await admin.from("ip_bans").upsert({
          ip, reason, active: true, banned_by: user.email
        }, { onConflict: "ip" });
        if (error) throw error;
        await logIp({ ip, action: "ban", user_email: user.email, detail: reason });
        return json({ ok: true });
      }
      if (action === "unban_ip") {
        const ip = String(body.ip || "").trim();
        if (!ip) return json({ error: "IP fehlt." }, 400);
        const { error } = await admin.from("ip_bans").update({ active: false }).eq("ip", ip);
        if (error) throw error;
        await logIp({ ip, action: "unban", user_email: user.email });
        return json({ ok: true });
      }
    }

    return json({ error: "Unbekannte Aktion." }, 400);
  } catch (e) {
    const msg = String((e as Error)?.message || e);
    const status = (e as { status?: number })?.status || (msg.startsWith("IP gesperrt") ? 403 : 500);
    return json({ error: msg }, status);
  }
});
