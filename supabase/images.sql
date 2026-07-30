-- Reader-uploaded images: attached to annotations, and added to a dossier's
-- visual contact list.
--
-- Run this once in the Supabase SQL editor, after moderation.sql.
-- It is safe to run twice.
--
-- Unlike avatars, these are stored in Supabase Storage rather than as data
-- URIs on the row. Avatars are tiny and change almost never, so carrying them
-- inline costs nothing. Photographs are the opposite: keeping them in the
-- table would mean every refresh of the annotation list re-downloaded every
-- picture ever posted. In Storage the row carries only a path, the list query
-- stays small, and the browser caches each image on its own.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('archive', 'archive', true, 1048576,
        array['image/webp', 'image/png', 'image/jpeg'])
on conflict (id) do update
  set public = true,
      file_size_limit = 1048576,
      allowed_mime_types = array['image/webp', 'image/png', 'image/jpeg'];

-- Anyone may look; the archive is readable without an account.
drop policy if exists "archive images are public" on storage.objects;
create policy "archive images are public"
  on storage.objects for select using (bucket_id = 'archive');

-- Uploads land in a folder named after the uploader, and the policy enforces
-- that, so nobody can write into anyone else's folder or overwrite their work.
drop policy if exists "upload into your own folder" on storage.objects;
create policy "upload into your own folder"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'archive'
    and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "remove your own uploads" on storage.objects;
create policy "remove your own uploads"
  on storage.objects for delete to authenticated
  using (bucket_id = 'archive'
    and ((storage.foldername(name))[1] = auth.uid()::text
      or exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_moderator)));

-- One picture attached to an annotation, as a path into the bucket above.
alter table public.annotations add column if not exists image text;

-- Pictures added to a file's visual record. target_kind and target_id match
-- the annotation columns, so personnel and lancer files can gain galleries
-- later without another migration.
create table if not exists public.images (
  id          uuid primary key default gen_random_uuid(),
  target_kind text not null,
  target_id   text not null,
  path        text not null,
  caption     text,
  author      uuid not null default auth.uid()
                references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

create index if not exists images_target_idx
  on public.images (target_kind, target_id, created_at);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'images_caption_len') then
    alter table public.images add constraint images_caption_len
      check (caption is null or char_length(caption) <= 120);
  end if;
end $$;

alter table public.images enable row level security;

drop policy if exists "images are readable" on public.images;
create policy "images are readable"
  on public.images for select using (true);

drop policy if exists "add your own image" on public.images;
create policy "add your own image"
  on public.images for insert to authenticated
  with check (author = auth.uid());

drop policy if exists "remove an image" on public.images;
create policy "remove an image"
  on public.images for delete to authenticated
  using (
    author = auth.uid()
    or exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.is_moderator)
  );
