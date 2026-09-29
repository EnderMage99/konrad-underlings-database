-- Sheets edited in the page: contact dossiers and personnel files.
--
-- Run this once in the Supabase SQL editor, after moderation.sql.
-- It is safe to run twice.
--
-- The page ships with every sheet baked into index.html. These two tables
-- hold the ones written or rewritten through the page's own editor: a row
-- named like a baked sheet replaces it at load, an unknown name is a new
-- sheet, and a hidden row drops one. Readable by anyone, so the page can
-- merge them in before a reader signs in; written only by the archivist, so
-- the record stays one person's. The whole sheet travels as one JSON
-- document in the shape the page already uses, which keeps the table free
-- of a column per stat and lets the editor grow without another migration.

create table if not exists public.contacts (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  faction    text not null,
  doc        jsonb not null,
  still      text,
  icon       text,
  added_on   date not null default current_date,
  hidden     boolean not null default false,
  author     uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);

create unique index if not exists contacts_name_key
  on public.contacts (lower(name));

create table if not exists public.personnel (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  faction    text not null,
  doc        jsonb not null,
  portrait   text,
  body       text,
  hidden     boolean not null default false,
  author     uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);

create unique index if not exists personnel_name_key
  on public.personnel (lower(name));

-- A sheet is a few kilobytes; a limit well above that guards against a
-- runaway paste without ever getting in the way of a real one.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'contacts_name_len') then
    alter table public.contacts add constraint contacts_name_len
      check (char_length(name) between 1 and 80);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'contacts_doc_len') then
    alter table public.contacts add constraint contacts_doc_len
      check (pg_column_size(doc) <= 65536);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'personnel_name_len') then
    alter table public.personnel add constraint personnel_name_len
      check (char_length(name) between 1 and 80);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'personnel_doc_len') then
    alter table public.personnel add constraint personnel_doc_len
      check (pg_column_size(doc) <= 65536);
  end if;
end $$;

alter table public.contacts enable row level security;
alter table public.personnel enable row level security;

drop policy if exists "contacts are readable" on public.contacts;
create policy "contacts are readable"
  on public.contacts for select using (true);

drop policy if exists "personnel are readable" on public.personnel;
create policy "personnel are readable"
  on public.personnel for select using (true);

-- Only the archivist writes. The same test guards every write on both
-- tables, so the four policies below are one rule stated four times.
drop policy if exists "archivist writes contacts" on public.contacts;
create policy "archivist writes contacts"
  on public.contacts for insert to authenticated
  with check (exists (select 1 from public.profiles p
                       where p.id = auth.uid() and p.is_moderator));

drop policy if exists "archivist rewrites contacts" on public.contacts;
create policy "archivist rewrites contacts"
  on public.contacts for update to authenticated
  using (exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_moderator))
  with check (exists (select 1 from public.profiles p
                       where p.id = auth.uid() and p.is_moderator));

drop policy if exists "archivist removes contacts" on public.contacts;
create policy "archivist removes contacts"
  on public.contacts for delete to authenticated
  using (exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_moderator));

drop policy if exists "archivist writes personnel" on public.personnel;
create policy "archivist writes personnel"
  on public.personnel for insert to authenticated
  with check (exists (select 1 from public.profiles p
                       where p.id = auth.uid() and p.is_moderator));

drop policy if exists "archivist rewrites personnel" on public.personnel;
create policy "archivist rewrites personnel"
  on public.personnel for update to authenticated
  using (exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_moderator))
  with check (exists (select 1 from public.profiles p
                       where p.id = auth.uid() and p.is_moderator));

drop policy if exists "archivist removes personnel" on public.personnel;
create policy "archivist removes personnel"
  on public.personnel for delete to authenticated
  using (exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_moderator));
