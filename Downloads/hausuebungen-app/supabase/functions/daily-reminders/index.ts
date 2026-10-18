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

function viennaParts(d = new Date()) {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Vienna",
    year: "numeric", month: "2-digit", day: "2-digit",
    weekday: "short", hour: "2-digit", minute: "2-digit", hour12: false
  });
  const parts = fmt.formatToParts(d);
  const get = (t: string) => parts.find(p => p.type === t)?.value || "";
  return {
    date: `${get("year")}-${get("month")}-${get("day")}`,
    weekday: get("weekday"),
    hour: Number(get("hour")),
    minute: Number(get("minute"))
  };
}

function addDaysISO(iso: string, days: number) {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() + days);
  return dt.toISOString().slice(0, 10);
}

function isWeekendISO(iso: string) {
  const [y, m, d] = iso.split("-").map(Number);
  const wd = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return wd === 0 || wd === 6;
}

/** Nächster Schultag relativ zu baseISO (exklusiv heute wenn daysAhead=1 vom Kalender) */
function schoolDayFrom(baseISO: string, offsetSchoolDays: number) {
  let cur = baseISO;
  let left = offsetSchoolDays;
  while (left > 0) {
    cur = addDaysISO(cur, 1);
    if (!isWeekendISO(cur)) left--;
  }
  return cur;
}

function timeMatches(remindTime: string, hour: number, minute: number, force: boolean) {
  if (force) return true;
  // remind_time "HH:MM:SS" or "HH:MM"
  const [h, mi] = String(remindTime || "10:00").split(":").map(Number);
  return hour === h && minute >= (mi || 0) && minute < (mi || 0) + 60;
}

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const body = await req.json().catch(() => ({}));
  const force = !!body.force; // Admin-Test: alle Stufen/Zeiten

  const cronOk = req.headers.get("x-cron-secret") === Deno.env.get("CRON_SECRET");
  let adminOk = false;
  const auth = req.headers.get("Authorization");
  if (!cronOk && auth) {
    const token = auth.replace(/^Bearer\s+/i, "");
    const { data: { user } } = await supabase.auth.getUser(token);
    adminOk = ["daweed@lukio.site", "nico@lukio.site"].includes((user?.email || "").toLowerCase());
  }
  if (!cronOk && !adminOk) return json({ error: "Unauthorized" }, 401);

  try {
    webpush.setVapidDetails(
      Deno.env.get("VAPID_SUBJECT") || "mailto:daweed@lukio.site",
      Deno.env.get("VAPID_PUBLIC_KEY")!,
      Deno.env.get("VAPID_PRIVATE_KEY")!
    );

    const now = viennaParts();
    const today = now.date;

    const [
      { data: settings },
      { data: personal },
      { data: classHu },
      { data: completions },
      { data: subs },
      { data: exams }
    ] = await Promise.all([
      supabase.from("user_settings").select("*"),
      supabase.from("hausuebungen").select("id,user_id,title,due,done"),
      supabase.from("klassen_huebungen").select("id,title,due"),
      supabase.from("class_hu_completions").select("class_hu_id,user_id,done"),
      supabase.from("push_subscriptions").select("id,user_id,subscription"),
      supabase.from("schularbeiten").select("id,title,subject,kind,exam_date")
    ]);

    const settingsByUser = new Map((settings || []).map(s => [s.user_id, s]));
    const defaultSettings = {
      notify_enabled: true,
      notify_class: true,
      notify_personal: true,
      remind_time: "10:00",
      stage_2d: false,
      stage_1d: true,
      stage_0d: false
    };

    let sent = 0;
    const users = new Set((subs || []).map(s => s.user_id));

    for (const userId of users) {
      const st = { ...defaultSettings, ...(settingsByUser.get(userId) || {}) };
      if (!st.notify_enabled) continue;
      if (!timeMatches(st.remind_time, now.hour, now.minute, force)) continue;

      const stages: { key: string; due: string; label: string }[] = [];
      if (st.stage_2d) {
        stages.push({ key: "2d", due: schoolDayFrom(today, 2), label: "in 2 Tagen" });
      }
      if (st.stage_1d) {
        const due = schoolDayFrom(today, 1);
        const weekend = isWeekendISO(addDaysISO(today, 1)) || isWeekendISO(addDaysISO(today, 2));
        stages.push({
          key: "1d",
          due,
          label: weekend && due > addDaysISO(today, 1) ? "Montag" : "morgen"
        });
      }
      if (st.stage_0d) {
        stages.push({ key: "0d", due: today, label: "heute" });
      }

      for (const stage of stages) {
        const titles: string[] = [];
        const keys: string[] = [];

        if (st.notify_personal) {
          for (const h of personal || []) {
            if (h.user_id !== userId || h.done || h.due !== stage.due) continue;
            const itemKey = `p:${h.id}`;
            const { data: already } = await supabase.from("reminder_sent")
              .select("id").eq("user_id", userId).eq("item_key", itemKey)
              .eq("stage", stage.key).eq("sent_on", today).maybeSingle();
            if (already && !force) continue;
            titles.push(h.title);
            keys.push(itemKey);
          }
        }

        if (st.notify_class) {
          const completed = new Set(
            (completions || [])
              .filter(c => c.user_id === userId && c.done)
              .map(c => c.class_hu_id)
          );
          for (const c of classHu || []) {
            if (c.due !== stage.due || completed.has(c.id)) continue;
            const itemKey = `c:${c.id}`;
            const { data: already } = await supabase.from("reminder_sent")
              .select("id").eq("user_id", userId).eq("item_key", itemKey)
              .eq("stage", stage.key).eq("sent_on", today).maybeSingle();
            if (already && !force) continue;
            titles.push(c.title);
            keys.push(itemKey);
          }
        }

        if (!titles.length) continue;

        const bodyText = titles.length === 1
          ? `${stage.label === "morgen" ? "Morgen" : stage.label === "heute" ? "Heute" : stage.label} fällig: ${titles[0]}`
          : `${titles.length} HÜ (${stage.label}): ${titles.slice(0, 3).join(", ")}${titles.length > 3 ? " …" : ""}`;

        const userSubs = (subs || []).filter(s => s.user_id === userId);
        for (const sub of userSubs) {
          try {
            await webpush.sendNotification(sub.subscription, JSON.stringify({
              title: "Erinnerung: Hausübungen",
              body: bodyText,
              tag: `daily-hu-${stage.key}`,
              url: "./#/"
            }));
            sent++;
          } catch (e) {
            const status = Number((e as { statusCode?: number })?.statusCode);
            if (status === 404 || status === 410) {
              await supabase.from("push_subscriptions").delete().eq("id", sub.id);
            }
          }
        }

        if (!force) {
          for (const itemKey of keys) {
            await supabase.from("reminder_sent").upsert({
              user_id: userId,
              item_key: itemKey,
              stage: stage.key,
              sent_on: today
            }, { onConflict: "user_id,item_key,stage,sent_on", ignoreDuplicates: true });
          }
        }
      }
    }

    // Tests / Schularbeiten: 7 Tage, 3 Tage, 1 Tag vorher (Kalendertage, ~ Erinnerungszeit)
    const examStages = [
      { key: "exam-7d", days: 7, label: "in einer Woche" },
      { key: "exam-3d", days: 3, label: "in 3 Tagen" },
      { key: "exam-1d", days: 1, label: "morgen" }
    ];
    for (const stage of examStages) {
      const target = addDaysISO(today, stage.days);
      const dueExams = (exams || []).filter(e => e.exam_date === target);
      if (!dueExams.length) continue;
      for (const userId of users) {
        const st = { ...defaultSettings, ...(settingsByUser.get(userId) || {}) };
        if (!st.notify_enabled) continue;
        if (!timeMatches(st.remind_time, now.hour, now.minute, force)) continue;
        for (const ex of dueExams) {
          const itemKey = `exam:${ex.id}`;
          const { data: already } = await supabase.from("reminder_sent")
            .select("id").eq("user_id", userId).eq("item_key", itemKey)
            .eq("stage", stage.key).eq("sent_on", today).maybeSingle();
          if (already && !force) continue;
          const kindL = ex.kind === "schularbeit" ? "Schularbeit" : "Test";
          const bodyText = `${kindL} ${stage.label}: ${ex.title}${ex.subject ? " (" + ex.subject + ")" : ""} · ${ex.exam_date}`;
          const userSubs = (subs || []).filter(s => s.user_id === userId);
          for (const sub of userSubs) {
            try {
              await webpush.sendNotification(sub.subscription, JSON.stringify({
                title: `${kindL}-Erinnerung`,
                body: bodyText,
                tag: `exam-${stage.key}-${ex.id}`,
                url: "./#/tests"
              }));
              sent++;
            } catch (e) {
              const status = Number((e as { statusCode?: number })?.statusCode);
              if (status === 404 || status === 410) {
                await supabase.from("push_subscriptions").delete().eq("id", sub.id);
              }
            }
          }
          if (!force) {
            await supabase.from("reminder_sent").upsert({
              user_id: userId,
              item_key: itemKey,
              stage: stage.key,
              sent_on: today
            }, { onConflict: "user_id,item_key,stage,sent_on", ignoreDuplicates: true });
          }
        }
      }
    }

    try {
      const { data: due } = await supabase.from("scheduled_pushes")
        .select("id,title,body").eq("sent", false).lte("send_at", new Date().toISOString());
      for (const job of due || []) {
        for (const sub of subs || []) {
          try {
            await webpush.sendNotification(sub.subscription, JSON.stringify({
              title: job.title || "Ankündigung",
              body: job.body,
              tag: "scheduled-" + job.id,
              url: "./#/"
            }));
            sent++;
          } catch { /* Gerät einzeln ignorieren */ }
        }
        await supabase.from("scheduled_pushes").update({ sent: true }).eq("id", job.id);
      }
    } catch { /* Tabelle optional */ }

    try {
      await supabase.from("app_settings").upsert([
        { key: "last_reminder_at", value: new Date().toISOString(), updated_at: new Date().toISOString() },
        { key: "last_reminder_sent", value: String(sent), updated_at: new Date().toISOString() }
      ]);
    } catch { /* ignore */ }

    return json({ date: today, hour: now.hour, sent, force });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
