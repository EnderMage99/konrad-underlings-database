-- Multiple characters per account.
--
-- Run this once in the Supabase SQL editor. It is safe to run twice.
--
-- Before: an account was one identity - profiles.callsign spoke every
-- annotation. After: profiles is just the account (and the is_moderator flag),
-- and annotations are spoken by a row in characters, of which an account may
-- keep any number.

create table if not exists public.characters (
  id         uuid primary key default gen_random_uuid(),
  owner      uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  callsign   text not null,
  title      text,
  avatar     text,
  created_at timestamptz not null default now()
);

create index if not exists characters_owner_idx on public.characters (owner);

alter table public.characters enable row level security;

-- Readable by anyone: the page has to name whoever filed an annotation,
-- including for readers who are not logged in.
drop policy if exists "characters are readable" on public.characters;
create policy "characters are readable"
  on public.characters for select using (true);

drop policy if exists "add your own character" on public.characters;
create policy "add your own character"
  on public.characters for insert to authenticated
  with check (owner = auth.uid());

drop policy if exists "edit your own character" on public.characters;
create policy "edit your own character"
  on public.characters for update to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());

drop policy if exists "retire your own character" on public.characters;
create policy "retire your own character"
  on public.characters for delete to authenticated
  using (owner = auth.uid());

-- Who spoke an annotation. Named "speaker" rather than "character" because
-- CHARACTER is a reserved word and would need quoting everywhere.
alter table public.annotations
  add column if not exists speaker uuid
    references public.characters (id) on delete cascade;

create index if not exists annotations_speaker_idx on public.annotations (speaker);

-- Carry each existing account over as its own first character, so nobody has
-- to re-enter a callsign they already set.
insert into public.characters (owner, callsign, avatar)
select p.id, p.callsign, p.avatar
  from public.profiles p
 where p.callsign is not null
   and not exists (select 1 from public.characters c where c.owner = p.id);

-- Existing annotations keep their attribution.
update public.annotations a
   set speaker = c.id
  from public.characters c
 where a.speaker is null
   and c.owner = a.author;

-- Filing an annotation now requires naming a character you own. Replaces
-- whatever insert policy is currently on the table, whatever it was called.
do $$
declare pol record;
begin
  for pol in select policyname from pg_policies
              where schemaname = 'public' and tablename = 'annotations'
                and cmd = 'INSERT'
  loop
    execute format('drop policy %I on public.annotations', pol.policyname);
  end loop;
end $$;

create policy "file an annotation as your own character"
  on public.annotations for insert to authenticated
  with check (
    author = auth.uid()
    and exists (
      select 1 from public.characters c
       where c.id = speaker and c.owner = auth.uid()
    )
  );
