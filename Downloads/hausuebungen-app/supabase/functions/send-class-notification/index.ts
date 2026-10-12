import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

const url = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(url, serviceKey);

function json(data: unknown, status = 200) {
  return Response.json(data, { status, headers: cors });
}

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const auth = req.headers.get("Authorization");
    if (!auth) return json({ error: "Unauthorized" }, 401);
    const token = auth.replace(/^Bearer\s+/i, "");
    const { data: { user }, error: userError } = await admin.auth.getUser(token);
    if (userError || !user) return json({ error: "Unauthorized" }, 401);

    const email = (user.email || "").toLowerCase();
    let allowed = ["daweed@lukio.site","nico@lukio.site"].includes(email);
    if (!allowed) {
      const { data } = await admin.from("klassen_hu_permissions")
        .select("can_write").eq("user_id", user.id).maybeSingle();
      allowed = !!data?.can_write;
    }
    if (!allowed) return json({ error: "Forbidden" }, 403);

    let payload: { title?: string; body?: string; tag?: string } = {};
    try { payload = await req.json(); } catch { payload = {}; }

    const title = payload.title || "Neue Klassen-HÜ";
    const body = payload.body || "Es wurde eine neue Hausübung in „Klassen HÜ“ hinzugefügt.";
    const tag = payload.tag || "class-hu";

    webpush.setVapidDetails(
      Deno.env.get("VAPID_SUBJECT") || "mailto:daweed@lukio.site",
      Deno.env.get("VAPID_PUBLIC_KEY")!,
      Deno.env.get("VAPID_PRIVATE_KEY")!
    );

    const { data: subs, error } = await admin.from("push_subscriptions").select("id,subscription");
    if (error) throw error;

    let sent = 0;
    const errors: string[] = [];
    for (const row of subs || []) {
      try {
        await webpush.sendNotification(row.subscription, JSON.stringify({
          title, body, tag, url: "./"
        }));
        sent++;
      } catch (e) {
        const status = Number((e as { statusCode?: number })?.statusCode);
        if (status === 404 || status === 410) await admin.from("push_subscriptions").delete().eq("id", row.id);
        else errors.push(String((e as Error)?.message || e));
      }
    }
    return json({ sent, total: (subs || []).length, errors: errors.slice(0, 3) });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
