# Hausübungen-App – Einrichtung

## 1. Datenbank
In Supabase **SQL Editor** den kompletten Inhalt von `supabase-setup.sql` ausführen.

Neu u. a.:
- `important` + `sort_order` bei persönlichen HÜ
- Tabelle `activity_logs`
- Funktion `set_class_hu_permission`

## 2. Storage
Bucket `hu-files` (privat, 10 GB Limit). Resumable Uploads (TUS).

## 3. Admin
`daweed@lukio.site` – Tab **Admin** für Schreibrechte + Aktivitäts-Log.  
User muss sich **einmal** angemeldet haben, bevor Rechte gesetzt werden können.

## 4. Push / VAPID
```bash
npx web-push generate-vapid-keys
```
`PUSH_VAPID_PUBLIC_KEY` in `config.js` setzen.

Secrets in Supabase Edge Functions:
```text
VAPID_SUBJECT=mailto:daweed@lukio.site
VAPID_PUBLIC_KEY=…
VAPID_PRIVATE_KEY=…
CRON_SECRET=…
```

## 5. Edge Functions
```bash
supabase functions deploy send-class-notification
supabase functions deploy daily-reminders
```

## 5b. Functions nach dieser Version neu deployen
```bash
supabase functions deploy send-class-notification
supabase functions deploy daily-reminders
```
Sonst funktionieren die Test-Buttons im Admin-Tab nicht.

## 6. Cron (Erinnerung 1 Tag vorher, ideal um 10:00 Wien)
HTTP POST an:
```text
https://pfyyhsxsmlsfepbjahyr.supabase.co/functions/v1/daily-reminders
```
Header: `x-cron-secret: DEIN_CRON_SECRET`  
Zeit: z. B. **08:00 UTC** ≈ 10:00 Wien (Sommerzeit beachten).

Die Function benachrichtigt für den **nächsten Schultag** (überspringt Sa/So → Montag).

## 7. Deployment
Hochladen: `index.html`, `style.css`, `config.js`, `manifest.json`, `sw.js`, `icon.jpg`

## Features
- Dark / Light Mode (System + manuell, gespeichert)
- Drag & Drop Sortierung (persönlich)
- Swipe: links = erledigt, rechts = löschen
- Fälligkeitsfarben: heute orange, morgen gelb, überfällig rot
- Fortschrittsbalken „X von Y erledigt“
- Morgen-Ansicht (nächster Schultag)
- Fächer-Chips: GGP, PH, SEW, RISL, RK, RE, Ethic, NWT, D, SOPK, AM, MEDT, GETE, E, GINF, ITSI
- Datei-Vorschau (PDF, Bilder, Text)
- Push: neue Klassen-HÜ + Erinnerung 1 Tag vorher
- Aktivitäts-Log (Admin)
- Wochen-Übersicht
- Filter: Fach, Datum, nur wichtig
- Wichtig-Flag (rote Umrandung, nur persönlich)
- Haptic Feedback (Vibration)
