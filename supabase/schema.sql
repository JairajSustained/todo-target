-- todo-target backup table. Run this once in your own Supabase project
-- (Dashboard > SQL Editor). One row per user. Row-level security keeps each
-- user's row private.

create table if not exists public.backups (
  user_id    uuid primary key default auth.uid(),
  payload    jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.backups enable row level security;

drop policy if exists "backups_select_own" on public.backups;
drop policy if exists "backups_insert_own" on public.backups;
drop policy if exists "backups_update_own" on public.backups;

create policy "backups_select_own" on public.backups
  for select to authenticated using (user_id = auth.uid());

create policy "backups_insert_own" on public.backups
  for insert to authenticated with check (user_id = auth.uid());

create policy "backups_update_own" on public.backups
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update on public.backups to authenticated;
