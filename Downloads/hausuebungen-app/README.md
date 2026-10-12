# Hausübungen – Klassen-App

Web-App (PWA) für persönliche und gemeinsame Hausübungen, Schulübungen, Dateien, Lösungen und Push-Erinnerungen.  
Gehostet z. B. auf Cloudflare Pages, Backend: **Supabase** (Auth, Datenbank, Storage, Edge Functions).

**Live:** `https://hausuebung.pages.dev` (Beispiel)

---

## Login & Accounts

| Aktion | Beschreibung |
|--------|----------------|
| **Anmelden** | Benutzername + Passwort (intern: `name@lukio.site`) |
| **Account erstellen** | Selbst registrieren (Benutzername, Passwort, Wiederholung) |
| **Passwort vergessen** | Code anfordern → Code geht an den **Admin** (Push + Admin-Liste) → neues Passwort setzen |
| **Abmelden** | Session beenden |

- Benutzername: 2–32 Zeichen, a–z, 0–9, `.` `_` `-`
- Passwort: mindestens 6 Zeichen
- Admins: **DaWeed** (`daweed@lukio.site`) und **Nico** (`nico@lukio.site`)

---

## Tabs im Überblick

### 1. Persönlich
Eigene Hausübungen – nur für dich sichtbar.

- Anlegen, bearbeiten, löschen  
- Fach, Titel, Fälligkeitsdatum, Notiz, **wichtig** (rote Markierung)  
- Anhänge (Fotos, PDF, …) bis ca. **10 GB**  
- Als erledigt markieren (Checkbox / Swipe)  
- Drag & Drop zum Sortieren  
- Filter: Fach, Datum, nur Wichtige  
- Statusfarben: heute (orange), morgen (gelb), überfällig (rot), erledigt (grün)

### 2. Klassen HÜ
Gemeinsame Hausaufgaben für die ganze Klasse.

- Lesen: **alle** angemeldeten User  
- Schreiben / Bearbeiten: nur mit **Schreibrecht** oder **Admin**  
- Zeigt, **wer** den Eintrag hinzugefügt hat  
- Pro User: „Als erledigt markieren“ (nur für dich)  
- Anhänge + **Lösungen** (jeder darf Lösungen hochladen; sichtbar für alle mit „von wem“)  
- Push an alle bei **neuer** Klassen-HÜ  

**Automatik um 23:59 (Wien) am Fälligkeitstag:**  
Klassen-HÜ wandert in **Persönlich** jedes Users (erledigt, wenn markiert) und wird aus Klassen HÜ gelöscht.

### 3. Unterlagen (Schulübungen / SÜ)
Material aus dem Unterricht posten (Titel, Fach, Datum, Notiz, Dateien).

- Schreibrechte = dieselben wie bei **Klassen HÜ**

### 4. Diese Woche
Übersicht: was diese Woche noch offen ist („Was habe ich diese Woche noch?“).

### 5. Admin *(nur DaWeed & Nico)*
- **Benutzer:** anlegen, umbenennen, Passwort ändern, löschen (in Supabase Auth)  
- **Schreibrechte:** Klassen-HÜ & SÜ erlauben / sperren (Live-Liste aus Auth)  
- **Passwort-Reset-Codes:** offene Codes anzeigen  
- **Benachrichtigungen testen:** lokal, Push an alle, 1-Tag-Erinnerung, Archiv-Test  
- **Aktivitäts-Log**

---

## Farben & Bedienung

| Status | Darstellung |
|--------|-------------|
| Erledigt | grüner Hintergrund / Streifen |
| Heute fällig | orange |
| Morgen fällig | gelb |
| Überfällig | rot |
| Wichtig | roter Rand (nur persönlich) |

- **Dark / Light Mode** (Sonne/Mond)  
- **Swipe** (Handy): links = erledigt, rechts = löschen (persönlich)  
- **Fortschrittsbalken** „X von Y erledigt“  
- **Morgen-Ansicht** / Wochenende: Erinnerungstext „Montag“ statt „morgen“  
- Datei-**Vorschau** in der App (Bilder, PDF, Text)  
- Haptic Feedback wo möglich  

**Fächer (Chips):**  
GGP, PH, SEW, RISL, RK, RE, Ethic, NWT, D, SOPK, AM, MEDT, GETE, E, GINF, ITSI

---

## Push-Benachrichtigungen

| Wann | Was |
|------|-----|
| Neue **Klassen-HÜ** | Push an alle Geräte mit Abo |
| **1 Tag vorher** ca. 10:00 | Offene persönliche + Klassen-HÜ (nicht erledigt) |
| Passwort-Reset / neuer Account | Push an **Admins** |

- Berechtigung: **einmal** beim ersten Start / ersten Nutzen  
- iOS: oft „Zum Home-Bildschirm“ nötig, Safari, Benachrichtigungen erlauben  
- Android: Chrome / Edge, Benachrichtigungen erlauben  
- Pro Account können **mehrere Geräte** registriert sein  

---

## Rollen

| Rolle | Kann |
|-------|------|
| **Normaler User** | Persönlich voll; Klassen/Unterlagen lesen; Lösungen hochladen; mit Recht schreiben |
| **Schreibrecht** | Klassen-HÜ & Unterlagen anlegen/bearbeiten (eigene/erlaubte) |
| **Admin (DaWeed, Nico)** | Alles + User-Verwaltung, Rechte, Tests, Logs, alle Löschen-Rechte |

---

## Technik (kurz)

| Teil | Stack |
|------|--------|
| Frontend | HTML / CSS / JS, Service Worker (PWA) |
| Backend | Supabase Auth, Postgres + RLS, Storage `hu-files` |
| Functions | `send-class-notification`, `daily-reminders`, `archive-class-hu`, `admin-users`, `auth-public` |
| Cron | Erinnerungen (~10:00), Archiv Klassen-HÜ (~23:59 Wien) |

Wichtige SQL-Datei für Neuaufbau: `HAUSUEBUNGEN-KOMPLETT.sql`

---

## Typischer Alltag

1. Login (oder Account erstellen)  
2. **Persönlich:** eigene To-dos pflegen  
3. **Klassen HÜ:** gemeinsame Aufgaben lesen / mit Recht eintragen  
4. Lösung hochladen, wenn fertig – Mitschüler sehen sie  
5. Abends: Erledigt markieren → am Fälligkeitstag wandert Klassen-HÜ in Persönlich  
6. Push anlassen, damit nichts untergeht  

---

## Support / Admin-Checkliste

- [ ] SQL `HAUSUEBUNGEN-KOMPLETT.sql` ausgeführt  
- [ ] Edge Functions mit `--no-verify-jwt` deployed  
- [ ] `config.js` mit `ADMIN_EMAILS` und VAPID-Key  
- [ ] Cron für `daily-reminders` und `archive-class-hu`  
- [ ] Admins einmal Push abonniert (für Reset-Codes)  
- [ ] Storage-Policies für Vorschau (im Komplett-SQL enthalten)  

Bei Fehlern: Admin → Benachrichtigungen testen; Browser-Konsole; Function-Logs in Supabase.
