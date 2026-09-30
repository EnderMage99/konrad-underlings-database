# Lancers page rework

Players open and write their own Lancer files. Nothing here is built yet.
Revised 2026-09-30 with author choice, pinned comments and the annotation move.

## Decisions taken

- Any character can open a Lancer file. The only gate is ownership.
- NHPs come from your own characters and may assist more than one Lancer.
- Frame is flavor. Name, frame and description are free text.
- Nebula's baked entry stays and is claimable, same as Star.
- Every file has a chosen author: the owner picks which of their characters
  wrote it. That goes for the Lancer's own file, each NHP's file and the
  mech's file.
- Comments are pinned, in-character remarks the owner adds, each with a chosen
  author. They stand above the annotations.
- Annotations sit directly under the file they concern, not at the foot of
  the card.

## What exists today

The Lancers tab renders a hardcoded array with Star and Nebula: pilot and mech
stat sheets, a baked file with a fixed `by`, baked comments from Overseer and
Star, and NHPs with their own files and comments. Characters, files,
annotations and image uploads are already live in Supabase. The baked `by`
values and comment authors resolve through a fixed COMMENTERS map, which is
what the author choice replaces.

## Layout per block

Each of the three kinds of block reads the same way, top to bottom:

1. Portrait (or mech picture) beside the file, with an author line under the
   file: the chosen character's avatar, callsign and title.
2. Comments: pinned remarks, each with its own author's avatar and name.
3. Annotations for that block.

The card is: Lancer head, Lancer block, then each NHP block, then the mech
block. Pilot and mech stat sheets go.

## Step 1. Schema

One migration, `supabase/lancers.sql`.

- `lancers`: id, character (unique, references characters), mech_name,
  mech_frame, mech_image, timestamps. The mech description moves out into a
  file of kind `mech`, so there is no description column.
- `lancer_nhps`: id, lancer, character, tag (default "Assisting NHP"),
  position. Unique on lancer plus character.
- `files` gains `written_by` (references characters, nullable). Null means
  "no author shown", which is how existing rows behave. The kinds in use
  become `lancer`, `nhp` and `mech`, all keyed by the callsign or NHP name.
- `comments`: id, target_kind, target_id, written_by (references characters),
  body (capped like annotations), position, created_at. This is the pinned
  remark table, separate from annotations.

Row-level security follows the existing pattern.

- `lancers` and `lancer_nhps`: anyone reads; insert, update, delete only if
  you own the character, or you are a moderator. Attaching an NHP needs
  ownership of both characters.
- `files.written_by`: on insert and update the chosen character must be one
  you own, or you are a moderator. The existing rule that you may only write a
  file for a name you hold a character for stays.
- `comments`: anyone reads; insert, update, delete when you own the file's
  character (the Lancer, the NHP, or the mech's Lancer) and you own the
  character named in `written_by`, or you are a moderator. Moderators may pick
  any character as author.

Mech images go in the existing bucket under the uploader's folder.

## Step 2. Page change

- Strip the pilot and mech stat sheets and their rendering helpers.
- Baked files and comments stay as fallbacks. Their `by` values keep resolving
  through the COMMENTERS map only until a database row exists for that target,
  after which the row's `written_by` character is shown instead.
- Load `lancers`, `lancer_nhps`, `files.written_by` and `comments` joined with
  characters, tolerating a missing table so the page works before the
  migration.
- Merge by callsign, database row over baked entry, field by field.
- Re-order the card as in "Layout per block". Annotation keys stay
  `lancer::Name`, `nhp::Name` and gain `mech::Name`, so existing annotations
  do not move.
- Claiming: an owner of a character called Star or Nebula sees the controls on
  the baked card. The first save creates the row, pre-filled from the baked
  values.

Controls, all ownership-gated, moderators on every card:

- Account panel: "Open a Lancer file" on every character.
- File editor (existing) gains a "Written by" picker listing your characters,
  on Lancer, NHP and mech files alike.
- "Write the mech": name, frame, image picker with the existing shrinker. The
  mech's prose is edited through the file editor like any other file.
- "Add a comment" under each file: text plus a "Written by" picker. Comments
  can be reordered and removed by the file's owner.
- "Add an NHP" listing your other characters, with an inline new-character
  shortcut. Reorder and remove on each attached NHP.

## Step 3. Rollout

1. Run the migration. The page keeps working unchanged until step 2 ships.
2. Ship the page change.
3. Star claims Star and the Nebula player claims Nebula. Both entries should
   read the same before and after except for the new controls and the moved
   annotations.

Size: about 120 lines of SQL, roughly 400 lines added against 250 removed in
`index.html`.

## Open question

Who may add a comment to a file: only the file's owner (choosing among their
own characters), or any signed-in reader speaking as one of their characters?
The plan assumes owner only, which matches the baked comments today, where
Star and Overseer remark on each other's files and both belong to Star.
