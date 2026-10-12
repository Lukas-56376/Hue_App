import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

const ADMINS = ["daweed@lukio.site", "nico@lukio.site"];
const isAdminEmail = (e: string) => ADMINS.includes((e || "").toLowerCase());


const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

function json(data: unknown, status = 200) {
  return Response.json(data, { status, headers: cors });
}

/** Heutiges Datum in Wien (YYYY-MM-DD) */
function viennaTodayISO() {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Vienna",
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  });
  const parts = fmt.formatToParts(new Date());
  const get = (t: string) => parts.find(p => p.type === t)!.value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const cronOk = req.headers.get("x-cron-secret") === Deno.env.get("CRON_SECRET");
    let adminOk = false;
    const auth = req.headers.get("Authorization");
    if (!cronOk && auth) {
      const token = auth.replace(/^Bearer\s+/i, "");
      const { data: { user } } = await supabase.auth.getUser(token);
      adminOk = isAdminEmail(user?.email || "");
    }
    if (!cronOk && !adminOk) return json({ error: "Forbidden" }, 403);

    const body = await req.json().catch(() => ({}));
    // Optional: anderes Datum testen (YYYY-MM-DD), sonst heute Wien
    const dueDay = typeof body.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.date)
      ? body.date
      : viennaTodayISO();

    const { data: classItems, error: cErr } = await supabase
      .from("klassen_huebungen")
      .select("id,title,subject,due,note")
      .eq("due", dueDay);
    if (cErr) throw cErr;

    if (!classItems?.length) {
      return json({ ok: true, date: dueDay, archived: 0, users: 0, message: "Keine Klassen-HÜ mit diesem Datum." });
    }

    const { data: usersPage, error: uErr } = await supabase.auth.admin.listUsers({ page: 1, perPage: 200 });
    if (uErr) throw uErr;
    const users = usersPage?.users || [];

    const { data: completions, error: coErr } = await supabase
      .from("class_hu_completions")
      .select("class_hu_id,user_id,done,done_at")
      .in("class_hu_id", classItems.map(c => c.id));
    if (coErr) throw coErr;

    const doneMap = new Map<string, { done: boolean; done_at: string | null }>();
    for (const c of completions || []) {
      doneMap.set(`${c.class_hu_id}:${c.user_id}`, {
        done: !!c.done,
        done_at: c.done_at || null
      });
    }

    let personalCreated = 0;
    const idsToDelete: string[] = [];

    for (const item of classItems) {
      for (const u of users) {
        if (!u.id) continue;
        const key = `${item.id}:${u.id}`;
        const status = doneMap.get(key);
        const done = !!status?.done;
        const row = {
          user_id: u.id,
          title: item.title,
          subject: item.subject || "",
          due: item.due,
          note: item.note
            ? `${item.note}\n\n(aus Klassen-HÜ)`
            : "Aus Klassen-HÜ übernommen",
          done,
          done_at: done ? (status?.done_at || new Date().toISOString()) : null,
          important: false
        };
        const { error: insErr } = await supabase.from("hausuebungen").insert(row);
        if (insErr) {
          // doppelte/fehlerhafte Zeilen nicht den ganzen Job killen
          console.error("insert personal", insErr.message);
          continue;
        }
        personalCreated++;
      }
      idsToDelete.push(item.id);
    }

    if (idsToDelete.length) {
      // Dateien + Completions hängen per ON DELETE CASCADE (falls so gesetzt)
      const { error: delErr } = await supabase
        .from("klassen_huebungen")
        .delete()
        .in("id", idsToDelete);
      if (delErr) throw delErr;
    }

    return json({
      ok: true,
      date: dueDay,
      class_items: classItems.length,
      personal_created: personalCreated,
      deleted_class_ids: idsToDelete.length,
      users: users.length
    });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
