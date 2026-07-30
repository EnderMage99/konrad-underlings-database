-- Player-written files.
--
-- Run this once in the Supabase SQL editor. It is safe to run twice.
--
-- A Lancer file and an NHP file are both prose written in character. Rather
-- than hand-assigning who may write which, the right to write a file is
-- derived from owning a character of that name: if your account holds a
-- character called "Unwavering Comet", you may write that NHP's file. No
-- mapping to maintain, and it follows a character if it changes hands.

create table if not exists public.files (
  id          uuid primary key default gen_random_uuid(),
  target_kind text not null,
  target_id   text not null,
  body        text not null,
  author      uuid references auth.users (id) on delete set null,
  updated_at  timestamptz not null default now(),
  unique (target_kind, target_id)
);

create index if not exists files_target_idx on public.files (target_kind, target_id);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'files_body_len') then
    alter table public.files add constraint files_body_len
      check (char_length(body) <= 8000);
  end if;
end $$;

alter table public.files enable row level security;

drop policy if exists "files are readable" on public.files;
create policy "files are readable"
  on public.files for select using (true);

-- The same test for writing a new file and for rewriting one, so a reader
-- cannot claim a file by name they do not hold a character for.
drop policy if exists "write a file you speak for" on public.files;
create policy "write a file you speak for"
  on public.files for insert to authenticated
  with check (
    exists (select 1 from public.characters c
             where c.owner = auth.uid()
               and lower(c.callsign) = lower(target_id))
    or exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.is_moderator)
  );

drop policy if exists "rewrite a file you speak for" on public.files;
create policy "rewrite a file you speak for"
  on public.files for update to authenticated
  using (
    exists (select 1 from public.characters c
             where c.owner = auth.uid()
               and lower(c.callsign) = lower(target_id))
    or exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.is_moderator)
  )
  with check (
    exists (select 1 from public.characters c
             where c.owner = auth.uid()
               and lower(c.callsign) = lower(target_id))
    or exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.is_moderator)
  );

drop policy if exists "withdraw a file you speak for" on public.files;
create policy "withdraw a file you speak for"
  on public.files for delete to authenticated
  using (
    exists (select 1 from public.characters c
             where c.owner = auth.uid()
               and lower(c.callsign) = lower(target_id))
    or exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.is_moderator)
  );
