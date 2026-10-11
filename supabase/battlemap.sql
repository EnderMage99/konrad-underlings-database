-- Battle maps: a shared hex board for planning sessions.
--
-- Run this once in the Supabase SQL editor, after lancers.sql (it uses
-- is_archivist()). It is safe to run twice.
--
-- A map is a background picture, a grid laid over it, and painted hexes,
-- all on one row. Everything standing on the map - dossier contacts, blank
-- tokens and props such as asteroids - is a row in battle_tokens. Anyone can
-- watch a map. The archivist builds it; any signed-in reader can move tokens
-- and retitle them while the table plans, but only the archivist adds,
-- removes, resizes or repictures them.

-- ---- maps ------------------------------------------------------------------

create table if not exists public.battlemaps (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  background  text,
  grid        jsonb not null default '{}'::jsonb,
  paint       jsonb not null default '{}'::jsonb,
  created_by  uuid references auth.users (id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---- tokens ----------------------------------------------------------------
-- q and r are axial hex coordinates of the token's anchor hex. size is the
-- Lancer size string ("1/2", "1", "2", "3", "4"); a prop ignores it and uses
-- scale instead. image overrides the dossier picture of a contact token.

create table if not exists public.battle_tokens (
  id          uuid primary key default gen_random_uuid(),
  map_id      uuid not null references public.battlemaps (id) on delete cascade,
  kind        text not null default 'custom',
  contact     text,
  label       text not null default '',
  color       text not null default '#B8434A',
  image       text,
  description text not null default '',
  size        text not null default '1',
  q           integer not null default 0,
  r           integer not null default 0,
  facing      real not null default 0,
  scale       real not null default 1,
  z           integer not null default 0,
  updated_by  uuid references auth.users (id) on delete set null default auth.uid(),
  updated_at  timestamptz not null default now()
);

create index if not exists battle_tokens_map on public.battle_tokens (map_id);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'battlemaps_name_len') then
    alter table public.battlemaps add constraint battlemaps_name_len
      check (char_length(name) between 1 and 80);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'battlemaps_paint_len') then
    alter table public.battlemaps add constraint battlemaps_paint_len
      check (pg_column_size(paint) <= 262144);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'battle_tokens_kind') then
    alter table public.battle_tokens add constraint battle_tokens_kind
      check (kind in ('contact', 'custom', 'prop'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'battle_tokens_text_len') then
    alter table public.battle_tokens add constraint battle_tokens_text_len
      check (char_length(label) <= 80 and char_length(description) <= 2000
             and char_length(color) <= 16 and char_length(size) <= 8);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'battle_tokens_scale') then
    alter table public.battle_tokens add constraint battle_tokens_scale
      check (scale between 0.1 and 40);
  end if;
end $$;

-- ---- stamps ----------------------------------------------------------------
-- updated_at and updated_by are set here, not trusted from the page.

create or replace function public.battle_stamp()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if tg_table_name = 'battle_tokens' then
    new.updated_by := auth.uid();
  end if;
  return new;
end $$;

drop trigger if exists battlemaps_stamp on public.battlemaps;
create trigger battlemaps_stamp before update on public.battlemaps
  for each row execute function public.battle_stamp();

drop trigger if exists battle_tokens_stamp on public.battle_tokens;
create trigger battle_tokens_stamp before insert or update on public.battle_tokens
  for each row execute function public.battle_stamp();

-- A reader who is not the archivist may move a token, turn it, and change
-- its label, colour and description. Anything else stays as it was.
create or replace function public.battle_token_guard()
returns trigger language plpgsql as $$
begin
  if public.is_archivist() then
    return new;
  end if;
  if new.map_id is distinct from old.map_id
     or new.kind is distinct from old.kind
     or new.contact is distinct from old.contact
     or new.image is distinct from old.image
     or new.size is distinct from old.size
     or new.scale is distinct from old.scale
     or new.z is distinct from old.z then
    raise exception 'Only the archivist can change that.';
  end if;
  return new;
end $$;

drop trigger if exists battle_tokens_guard on public.battle_tokens;
create trigger battle_tokens_guard before update on public.battle_tokens
  for each row execute function public.battle_token_guard();

-- ---- row level security ----------------------------------------------------

alter table public.battlemaps enable row level security;
alter table public.battle_tokens enable row level security;

drop policy if exists "battlemaps are readable" on public.battlemaps;
create policy "battlemaps are readable"
  on public.battlemaps for select using (true);

drop policy if exists "archivist writes battlemaps" on public.battlemaps;
create policy "archivist writes battlemaps"
  on public.battlemaps for insert to authenticated
  with check (public.is_archivist());

drop policy if exists "archivist rewrites battlemaps" on public.battlemaps;
create policy "archivist rewrites battlemaps"
  on public.battlemaps for update to authenticated
  using (public.is_archivist()) with check (public.is_archivist());

drop policy if exists "archivist removes battlemaps" on public.battlemaps;
create policy "archivist removes battlemaps"
  on public.battlemaps for delete to authenticated
  using (public.is_archivist());

drop policy if exists "battle tokens are readable" on public.battle_tokens;
create policy "battle tokens are readable"
  on public.battle_tokens for select using (true);

drop policy if exists "archivist places battle tokens" on public.battle_tokens;
create policy "archivist places battle tokens"
  on public.battle_tokens for insert to authenticated
  with check (public.is_archivist());

-- Any signed-in reader may update; battle_token_guard limits what to.
drop policy if exists "readers move battle tokens" on public.battle_tokens;
create policy "readers move battle tokens"
  on public.battle_tokens for update to authenticated
  using (true) with check (true);

drop policy if exists "archivist removes battle tokens" on public.battle_tokens;
create policy "archivist removes battle tokens"
  on public.battle_tokens for delete to authenticated
  using (public.is_archivist());

-- ---- realtime --------------------------------------------------------------
-- Saved changes reach open pages through the realtime publication. Deletes
-- need the whole old row to say which map they came from.

alter table public.battle_tokens replica identity full;

do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'battlemaps') then
    alter publication supabase_realtime add table public.battlemaps;
  end if;
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'battle_tokens') then
    alter publication supabase_realtime add table public.battle_tokens;
  end if;
end $$;
