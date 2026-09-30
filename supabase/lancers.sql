-- Player-made Lancer files.
--
-- Run this once in the Supabase SQL editor, after files.sql and images.sql.
-- It is safe to run twice.
--
-- A Lancer is a character with a file of its own: a mech, some assisting NHPs
-- drawn from the same account's other characters, and prose. The prose lives
-- in the existing files table under three kinds - "lancer", "nhp" and "mech" -
-- each keyed by the callsign, so the right to write it still comes from
-- owning a character of that name. Two things are new here: a file may name
-- which character wrote it, and a file may carry pinned comments, each in the
-- voice of a character the owner picks.

-- ---- helpers ---------------------------------------------------------------
-- Both are plain reads of world-readable tables, so no security definer.

create or replace function public.is_archivist()
returns boolean language sql stable as $$
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_moderator);
$$;

-- You speak for a name when a character of yours carries it.
create or replace function public.speaks_for(target text)
returns boolean language sql stable as $$
  select exists (select 1 from public.characters c
                  where c.owner = auth.uid()
                    and lower(c.callsign) = lower(target));
$$;

create or replace function public.owns_character(ch uuid)
returns boolean language sql stable as $$
  select exists (select 1 from public.characters c
                  where c.id = ch and c.owner = auth.uid());
$$;

-- ---- lancers ---------------------------------------------------------------
-- One row per character that has opened a Lancer file. "pilot" rather than
-- "character", which is a reserved word. No stat columns: the frame is
-- flavor, and everything else is prose in the files table.

create table if not exists public.lancers (
  id          uuid primary key default gen_random_uuid(),
  pilot       uuid not null unique
                references public.characters (id) on delete cascade,
  mech_name   text,
  mech_frame  text,
  mech_image  text,
  hidden_comments jsonb not null default '[]',   -- baked comments the owner removed
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.lancers
  add column if not exists hidden_comments jsonb not null default '[]';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'lancers_mech_len') then
    alter table public.lancers add constraint lancers_mech_len
      check (char_length(coalesce(mech_name, '')) <= 60
         and char_length(coalesce(mech_frame, '')) <= 60);
  end if;
end $$;

alter table public.lancers enable row level security;

drop policy if exists "lancers are readable" on public.lancers;
create policy "lancers are readable"
  on public.lancers for select using (true);

drop policy if exists "open a lancer file for your own character" on public.lancers;
create policy "open a lancer file for your own character"
  on public.lancers for insert to authenticated
  with check (public.owns_character(pilot) or public.is_archivist());

drop policy if exists "keep your own lancer file" on public.lancers;
create policy "keep your own lancer file"
  on public.lancers for update to authenticated
  using (public.owns_character(pilot) or public.is_archivist())
  with check (public.owns_character(pilot) or public.is_archivist());

drop policy if exists "close your own lancer file" on public.lancers;
create policy "close your own lancer file"
  on public.lancers for delete to authenticated
  using (public.owns_character(pilot) or public.is_archivist());

-- ---- assisting NHPs ---------------------------------------------------------
-- An NHP is another character on the same account, attached to a Lancer.
-- Unique on the pair, so one NHP may serve several Lancers but never appears
-- twice on one.

create table if not exists public.lancer_nhps (
  id        uuid primary key default gen_random_uuid(),
  lancer    uuid not null references public.lancers (id) on delete cascade,
  nhp       uuid not null references public.characters (id) on delete cascade,
  tag       text not null default 'Assisting NHP',
  position  integer not null default 0,
  unique (lancer, nhp)
);

create index if not exists lancer_nhps_lancer_idx on public.lancer_nhps (lancer, position);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'lancer_nhps_tag_len') then
    alter table public.lancer_nhps add constraint lancer_nhps_tag_len
      check (char_length(tag) between 1 and 40);
  end if;
end $$;

alter table public.lancer_nhps enable row level security;

-- The Lancer's owner decides who assists.
create or replace function public.owns_lancer(l uuid)
returns boolean language sql stable as $$
  select exists (select 1 from public.lancers x
                   join public.characters c on c.id = x.pilot
                  where x.id = l and c.owner = auth.uid());
$$;

drop policy if exists "nhps are readable" on public.lancer_nhps;
create policy "nhps are readable"
  on public.lancer_nhps for select using (true);

drop policy if exists "attach your own character as an nhp" on public.lancer_nhps;
create policy "attach your own character as an nhp"
  on public.lancer_nhps for insert to authenticated
  with check ((public.owns_lancer(lancer) and public.owns_character(nhp))
              or public.is_archivist());

drop policy if exists "reorder your own nhps" on public.lancer_nhps;
create policy "reorder your own nhps"
  on public.lancer_nhps for update to authenticated
  using (public.owns_lancer(lancer) or public.is_archivist())
  with check (public.owns_lancer(lancer) or public.is_archivist());

drop policy if exists "detach your own nhps" on public.lancer_nhps;
create policy "detach your own nhps"
  on public.lancer_nhps for delete to authenticated
  using (public.owns_lancer(lancer) or public.is_archivist());

-- ---- who wrote a file -------------------------------------------------------
-- Null keeps today's behaviour: the byline names the file's subject.

alter table public.files
  add column if not exists written_by uuid
    references public.characters (id) on delete set null;

-- The write policies gain one test: a named author must be a character you
-- own. The archivist may name anyone.
drop policy if exists "write a file you speak for" on public.files;
create policy "write a file you speak for"
  on public.files for insert to authenticated
  with check (
    (public.speaks_for(target_id)
      and (written_by is null or public.owns_character(written_by)))
    or public.is_archivist()
  );

drop policy if exists "rewrite a file you speak for" on public.files;
create policy "rewrite a file you speak for"
  on public.files for update to authenticated
  using (public.speaks_for(target_id) or public.is_archivist())
  with check (
    (public.speaks_for(target_id)
      and (written_by is null or public.owns_character(written_by)))
    or public.is_archivist()
  );

-- ---- pinned comments --------------------------------------------------------
-- In-character remarks that stand above the annotations on a file. Only the
-- file's owner adds them, speaking as one of their own characters; separate
-- from annotations, which anyone files as themselves.

create table if not exists public.comments (
  id          uuid primary key default gen_random_uuid(),
  target_kind text not null,
  target_id   text not null,
  written_by  uuid not null references public.characters (id) on delete cascade,
  body        text not null,
  position    integer not null default 0,
  author      uuid not null default auth.uid()
                references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

create index if not exists comments_target_idx
  on public.comments (target_kind, target_id, position, created_at);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'comments_body_len') then
    alter table public.comments add constraint comments_body_len
      check (char_length(body) between 1 and 2000);
  end if;
end $$;

alter table public.comments enable row level security;

drop policy if exists "comments are readable" on public.comments;
create policy "comments are readable"
  on public.comments for select using (true);

drop policy if exists "pin a comment on a file you speak for" on public.comments;
create policy "pin a comment on a file you speak for"
  on public.comments for insert to authenticated
  with check (
    (public.speaks_for(target_id) and public.owns_character(written_by))
    or public.is_archivist()
  );

drop policy if exists "reorder comments on a file you speak for" on public.comments;
create policy "reorder comments on a file you speak for"
  on public.comments for update to authenticated
  using (public.speaks_for(target_id) or public.is_archivist())
  with check (
    (public.speaks_for(target_id) and public.owns_character(written_by))
    or public.is_archivist()
  );

drop policy if exists "unpin a comment on a file you speak for" on public.comments;
create policy "unpin a comment on a file you speak for"
  on public.comments for delete to authenticated
  using (public.speaks_for(target_id) or public.is_archivist());
