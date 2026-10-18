# Hausübungen

Web-App für persönliche Hausübungen, Klassen-HÜ und Unterlagen.

## Dateien
- `index.html`, `style.css`, `config.js`, `sw.js`, `manifest.json`, `icon.jpg`
- `supabase/functions/` — Edge Functions (nicht umbauen, nur deployen)
- `HAUSUEBUNGEN-KOMPLETT.sql` — einmal im SQL Editor, falls das Schema fehlt

## Accounts
Anmeldung mit Benutzername. Intern wird daraus `name@lukio.site`.
Admins: `daweed@lukio.site`, `nico@lukio.site`.

## Deploy
Statische Dateien auf Cloudflare Pages. Functions:

```
supabase functions deploy auth-public --no-verify-jwt
supabase functions deploy admin-users --no-verify-jwt
supabase functions deploy send-class-notification --no-verify-jwt
supabase functions deploy daily-reminders --no-verify-jwt
supabase functions deploy archive-class-hu --no-verify-jwt
```
