import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

function json(data: unknown, status = 200) {
  return Response.json(data, { status, headers: cors });
}

function weekendNow() {
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone: "Europe/Vienna", weekday: "short" });
  const wd = fmt.format(new Date()); // Sat, Sun, Mon, ...
  return wd === "Sat" || wd === "Sun";
}

function nextSchoolDayISO() {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Vienna", year: "numeric", month: "2-digit", day: "2-digit", weekday: "short"
  });
  const d = new Date();
  for (let i = 1; i <= 4; i++) {
    const candidate = new Date(d.getTime() + i * 24 * 60 * 60 * 1000);
    const parts = fmt.formatToParts(candidate);
    const get = (t: string) => parts.find(p => p.type === t)!.value;
    const wd = get("weekday");
    if (wd !== "Sat" && wd !== "Sun") return `${get("year")}-${get("month")}-${get("day")}`;
  }
  const t = new Date(d.getTime() + 24 * 60 * 60 * 1000);
  const parts = fmt.formatToParts(t);
  const get = (x: string) => parts.find(p => p.type === x)!.value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const cronOk = req.headers.get("x-cron-secret") === Deno.env.get("CRON_SECRET");
  let adminOk = false;
  const auth = req.headers.get("Authorization");
  if (!cronOk && auth) {
    const token = auth.replace(/^Bearer\s+/i, "");
    const { data: { user } } = await supabase.auth.getUser(token);
    adminOk = ["daweed@lukio.site","nico@lukio.site"].includes((user?.email || "").toLowerCase());
  }
  if (!cronOk && !adminOk) return json({ error: "Unauthorized" }, 401);

  try {
    webpush.setVapidDetails(
      Deno.env.get("VAPID_SUBJECT") || "mailto:daweed@lukio.site",
      Deno.env.get("VAPID_PUBLIC_KEY")!,
      Deno.env.get("VAPID_PRIVATE_KEY")!
    );

    const target = nextSchoolDayISO();
    const [{ data: personal }, { data: classHu }, { data: completions }, { data: subs }] = await Promise.all([
      supabase.from("hausuebungen").select("user_id,title").eq("due", target).eq("done", false),
      supabase.from("klassen_huebungen").select("id,title").eq("due", target),
      supabase.from("class_hu_completions").select("class_hu_id,user_id").eq("done", true),
      supabase.from("push_subscriptions").select("id,user_id,subscription")
    ]);

    const personalByUser = new Map<string, string[]>();
    for (const h of personal || []) {
      const arr = personalByUser.get(h.user_id) || [];
      arr.push(h.title);
      personalByUser.set(h.user_id, arr);
    }

    let sent = 0;
    for (const sub of subs || []) {
      const own = personalByUser.get(sub.user_id) || [];
      const completed = new Set((completions || []).filter(x => x.user_id === sub.user_id).map(x => x.class_hu_id));
      const classTitles = (classHu || []).filter(x => !completed.has(x.id)).map(x => x.title);
      const count = own.length + classTitles.length;
      if (!count) continue;

      const titles = [...own, ...classTitles].slice(0, 3);
      const when = weekendNow() ? "Montag" : "morgen";
      const body = count === 1
        ? `${when === "Montag" ? "Montag" : "Morgen"} fällig: ${titles[0]}`
        : `${count} Hausübungen für ${when === "Montag" ? "Montag" : "den nächsten Schultag"}: ${titles.join(", ")}${count > 3 ? " …" : ""}`;

      try {
        await webpush.sendNotification(sub.subscription, JSON.stringify({
          title: "Erinnerung: Hausübungen",
          body,
          tag: "daily-hu-reminder",
          url: "./"
        }));
        sent++;
      } catch (e) {
        const status = Number((e as { statusCode?: number })?.statusCode);
        if (status === 404 || status === 410) {
          await supabase.from("push_subscriptions").delete().eq("id", sub.id);
        }
      }
    }
    return json({ date: target, sent });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
