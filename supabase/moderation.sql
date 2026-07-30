-- Moderator removals, length limits, and closing a self-promotion hole.
--
-- Run this once in the Supabase SQL editor, after characters.sql.
-- It is safe to run twice.

-- Length limits, matching what the page enforces in the form. The page is the
-- only client today, but a constraint here is what actually guarantees it.
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'characters_callsign_len') then
    alter table public.characters add constraint characters_callsign_len
      check (char_length(callsign) between 2 and 24);
  end if;
  if not exists (select 1 from pg_constraint
                  where conname = 'characters_title_len') then
    alter table public.characters add constraint characters_title_len
      check (title is null or char_length(title) <= 24);
  end if;
end $$;

-- A removed annotation keeps its row and its attribution, but the text itself
-- is blanked rather than merely hidden. The annotations table is world
-- readable, so hiding it in the page would leave it plainly readable over the
-- API - the words have to actually go.
alter table public.annotations
  add column if not exists removed_at timestamptz,
  add column if not exists removed_by uuid references auth.users (id)
    on delete set null;

-- Authors may edit their own; archivists may remove anyone's. The page only
-- ever uses this to blank the text and stamp the tombstone.
drop policy if exists "remove an annotation" on public.annotations;
create policy "remove an annotation"
  on public.annotations for update to authenticated
  using (
    author = auth.uid()
    or exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.is_moderator)
  )
  with check (
    author = auth.uid()
    or exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.is_moderator)
  );

-- Archivists may also delete outright, tombstone and all.
drop policy if exists "delete an annotation" on public.annotations;
create policy "delete an annotation"
  on public.annotations for delete to authenticated
  using (
    author = auth.uid()
    or exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.is_moderator)
  );

-- Serio Zeal becomes the archivist.
update public.profiles set is_moderator = true where callsign = 'Star';

-- This account's callsign was a placeholder; its character is Lyxie.
update public.profiles set callsign = 'Lyxie'
 where callsign = 'Barry B. Benson';

-- Nobody can promote themselves. Row-level security decides which *rows* you
-- may touch, not which columns, so without this the policy below would let any
-- signed-in reader set their own is_moderator. Revoked before the policy
-- exists, so there is no window in which self-promotion is possible.
revoke update (is_moderator) on public.profiles from authenticated;
revoke update (is_moderator) on public.profiles from anon;

-- With that column out of reach, accounts may edit their own row, which is
-- what lets a reader fix the callsign they typed at signup.
drop policy if exists "edit your own account" on public.profiles;
create policy "edit your own account"
  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'profiles_callsign_len') then
    alter table public.profiles add constraint profiles_callsign_len
      check (char_length(callsign) between 2 and 24);
  end if;
end $$;
