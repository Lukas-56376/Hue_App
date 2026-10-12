-- Codes für Passwort-Reset (nur Service Role / Edge Functions)
create table if not exists public.password_resets (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  code text not null,
  expires_at timestamptz not null,
  used boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists password_resets_email_idx on public.password_resets(email);
create index if not exists password_resets_open_idx on public.password_resets(used, expires_at);

alter table public.password_resets enable row level security;
-- Keine Policies für authenticated: nur Service Role (Edge Function) greift zu
