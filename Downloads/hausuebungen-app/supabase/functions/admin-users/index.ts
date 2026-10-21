import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

const ADMINS = ["daweed@lukio.site", "nico@lukio.site"];
const SUPER_ADMINS = ["daweed@lukio.site"];
const isAdminEmail = (e: string) => ADMINS.includes((e || "").toLowerCase());
const isSuperAdminEmail = (e: string) => SUPER_ADMINS.includes((e || "").toLowerCase());
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

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const auth = req.headers.get("Authorization");
    if (!auth) return json({ error: "Unauthorized" }, 401);
    const token = auth.replace(/^Bearer\s+/i, "");
    const { data: { user }, error: userError } = await admin.auth.getUser(token);
    if (userError || !user) return json({ error: "Unauthorized" }, 401);
    if (!isAdminEmail(user.email || "")) return json({ error: "Forbidden" }, 403);

    const body = await req.json().catch(() => ({}));
    const action = String(body.action || "list");

    if (action === "list") {
      const { data, error } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
      if (error) throw error;
      const users = (data.users || []).map(u => ({
        id: u.id,
        email: u.email,
        name: (u.email || "").split("@")[0],
        created_at: u.created_at,
        last_sign_in_at: u.last_sign_in_at
      })).sort((a, b) => a.name.localeCompare(b.name, "de"));
      return json({ users });
    }

    if (action === "create") {
      const name = normName(body.username);
      const password = String(body.password || "");
      if (!/^[a-z0-9._-]{2,32}$/.test(name)) return json({ error: "Ungültiger Benutzername." }, 400);
      if (password.length < 6) return json({ error: "Passwort mindestens 6 Zeichen." }, 400);
      const email = `${name}@${DOMAIN}`;
      const { data, error } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true
      });
      if (error) throw error;
      return json({ ok: true, user: { id: data.user?.id, email } });
    }

    if (action === "password") {
      const id = String(body.userId || "");
      const password = String(body.password || "");
      if (!id || password.length < 6) return json({ error: "User und Passwort (min. 6) nötig." }, 400);
      const { error } = await admin.auth.admin.updateUserById(id, {
        password,
        user_metadata: { otp_pending: false }
      });
      if (error) throw error;
      return json({ ok: true });
    }

    if (action === "otp_password") {
      const id = String(body.userId || "");
      if (!id) return json({ error: "userId fehlt." }, 400);
      const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
      let password = "";
      const arr = new Uint8Array(10);
      crypto.getRandomValues(arr);
      for (let i = 0; i < 10; i++) password += chars[arr[i] % chars.length];
      const { data: target, error: getErr } = await admin.auth.admin.getUserById(id);
      if (getErr || !target?.user) return json({ error: "User nicht gefunden." }, 404);
      if (isAdminEmail(target.user.email || "") && !isSuperAdminEmail(user.email || "")) {
        return json({ error: "Admin-OTP nur durch Super-Admin." }, 403);
      }
      const meta = { ...(target.user.user_metadata || {}), otp_pending: true, otp_created_at: new Date().toISOString() };
      const { error } = await admin.auth.admin.updateUserById(id, { password, user_metadata: meta });
      if (error) throw error;
      return json({
        ok: true,
        password,
        email: target.user.email,
        name: (target.user.email || "").split("@")[0]
      });
    }

    if (action === "rename") {
      const id = String(body.userId || "");
      const name = normName(body.username);
      if (!id || !/^[a-z0-9._-]{2,32}$/.test(name)) return json({ error: "Ungültiger Name." }, 400);
      const email = `${name}@${DOMAIN}`;
      if (isAdminEmail(email)) return json({ error: "Admin-Namen sind fest." }, 400);
      const { error } = await admin.auth.admin.updateUserById(id, { email, email_confirm: true });
      if (error) throw error;
      await admin.from("klassen_hu_permissions").update({ user_email: email }).eq("user_id", id);
      return json({ ok: true, email });
    }

    if (action === "delete") {
      const id = String(body.userId || "");
      if (!id) return json({ error: "userId fehlt." }, 400);
      if (id === user.id) return json({ error: "Du kannst dich nicht selbst löschen." }, 400);
      const { data: target } = await admin.auth.admin.getUserById(id);
      if (isAdminEmail(target.user?.email || "")) return json({ error: "Admin nicht löschen." }, 400);
      await admin.from("klassen_huebungen").update({
        created_by: user.id,
        created_by_email: ADMIN,
        created_by_name: ADMIN.split("@")[0]
      }).eq("created_by", id);
      await admin.from("activity_logs").delete().eq("user_id", id);
      await admin.from("push_subscriptions").delete().eq("user_id", id);
      await admin.from("hausuebungen").delete().eq("user_id", id);
      await admin.from("klassen_hu_permissions").delete().eq("user_id", id);
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) throw error;
      return json({ ok: true });
    }

    if (action === "kick_push") {
      const name = normName(body.username || "");
      const id = String(body.userId || "");
      let targetId = id;
      if (!targetId && name) {
        const { data } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
        const found = (data?.users || []).find(u => (u.email || "").toLowerCase() === `${name}@${DOMAIN}`);
        if (!found) return json({ error: "User nicht gefunden." }, 404);
        targetId = found.id;
      }
      if (!targetId) return json({ error: "User fehlt." }, 400);
      const { error, count } = await admin.from("push_subscriptions").delete({ count: "exact" }).eq("user_id", targetId);
      if (error) throw error;
      return json({ ok: true, removed: count || 0 });
    }

    if (action === "impersonate") {
      if (!isSuperAdminEmail(user.email || "")) return json({ error: "Nur Super-Admin." }, 403);
      const id = String(body.userId || "");
      const name = normName(body.username || "");
      let targetEmail = "";
      let targetId = id;
      if (targetId) {
        const { data: target } = await admin.auth.admin.getUserById(targetId);
        targetEmail = target.user?.email || "";
      } else if (name) {
        targetEmail = `${name}@${DOMAIN}`;
        const { data } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
        const found = (data?.users || []).find(u => (u.email || "").toLowerCase() === targetEmail);
        if (!found) return json({ error: "User nicht gefunden." }, 404);
        targetId = found.id;
        targetEmail = found.email || targetEmail;
      } else {
        return json({ error: "User fehlt." }, 400);
      }
      if (!targetEmail) return json({ error: "Keine E-Mail." }, 400);
      if ((targetEmail || "").toLowerCase() === (user.email || "").toLowerCase()) {
        return json({ error: "Du bist bereits dieser User." }, 400);
      }
      const { data: linkData, error: linkErr } = await admin.auth.admin.generateLink({
        type: "magiclink",
        email: targetEmail
      });
      if (linkErr) throw linkErr;
      const hashed = linkData?.properties?.hashed_token;
      if (!hashed) return json({ error: "Token konnte nicht erzeugt werden." }, 500);
      return json({
        ok: true,
        token_hash: hashed,
        email: targetEmail,
        user_id: targetId,
        name: targetEmail.split("@")[0]
      });
    }

    return json({ error: "Unbekannte Aktion." }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
