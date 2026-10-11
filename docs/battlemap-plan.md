# Battle map plan

A shared hex grid where the archivist lays out a battlefield and everyone at
the table moves tokens on it live.

Drafted 2026-10-11.

Status 2026-10-11: built. `supabase/battlemap.sql`, `battlemap.html` (contacts baked by
`tools/battle-contacts.sh`) and the "Battle map" tab are in; tested in headless
Chrome against a mocked server. Waiting on the SQL run and a live test with
two accounts.

Not planned: fog of war, dice, measuring, line of sight, initiative. This
is a visual board for planning sessions, not a game engine.

## Decisions taken

- A page of its own, `battlemap.html`, linked from the Record Index row the
  way the Star chart is. It stands alone and copies the palette, the warp
  transition and the session helpers from `starmap.html`.
- Live and shared: the archivist and the players are on the same map at
  once, and a move shows up for everyone within a second.
- No library. Live updates go over a plain WebSocket to Supabase Realtime,
  spoken by hand like the rest of the page speaks REST. If the socket drops,
  the page falls back to polling every 2 seconds, so it never stops working.
- Battlefields are a background image plus painted hexes. Both are saved to
  the site, so a map can be reopened anywhere and shared as a link.
- Tokens come from the dossiers (picture, size, stats filled in) or are made
  blank. Any token can be renamed, recoloured, given a picture and given a
  description, whatever it started as.
- Sign-in stays on the main archive. The map reads the same session from
  localStorage, as the Star chart does.

## What exists today

The site is plain HTML with no dependencies. `index.html` holds the
dossiers; `starmap.html` is a standalone page that reuses the archive's
session (`overseer.session`), checks `profiles.is_moderator` for archivist
rights, and syncs ship moves by polling the `files` table. Pictures upload
as WebP to the public `archive` bucket under the uploader's own folder,
capped at 1 MB. Contact pictures are found by `iconOf(name)` and
`stillOf(name)`, and a contact's `size` is a string: "1/2", "1", "2", "3",
"4" or "?".

## Roles on the map

1. Archivist (`is_moderator`): builds the board. Creates and deletes maps,
   sets the background and grid, paints hexes, and adds, repictures,
   resizes and deletes tokens and props.
2. Signed-in reader: plans on it. Moves and turns any token, and edits its
   label, colour and description.
3. Signed out: watches. Sees moves live, can pan and zoom.

## The look

Modelled on the table the campaign plays on in Tabletop Simulator, but
straight top-down only: no camera tilt, no 3D.

- The background image fills the play area. In the reference it is a teal
  nebula over a dark starfield.
- Thin dim-red hex outlines over the whole area. Hexes outside the play area
  are still drawn, over a darker, flat ground, so the edge reads clearly.
- Each token stands on a base: its footprint hexes filled in a muted version
  of the token's colour (the reference uses a dark red for hostiles), with
  the token's picture drawn on top, larger than one hex and seen from above.
- Painted hexes are solid tiles: a fill, a lighter inner bevel, and an
  optional small label or icon. Grey for walls, green for objectives, a
  translucent colour for zones.
- Props are pictures that ignore the grid's footprint rules: asteroids,
  wreckage, a station bridge. They can be scaled and rotated freely and sit
  below tokens.
- Movement is smooth. A dragged token follows the pointer exactly, with a
  faint outline of the hexes it would land on, and snaps to them when it is
  dropped. Other viewers see the drag glide, not jump.
- The interface stays out of the way: small chamfered panels at the edges in
  the archive's colours, so the map is most of the screen.

## The grid

- Axial hex coordinates (q, r). Flat-top by default, as in the reference
  (walls there run down the map as zigzag columns), with pointy-top as a
  per-map setting.
- Per map: hex size in pixels and an x/y offset, so the grid can be lined
  up over a background that already has hexes drawn on it.
- Grid line colour and opacity per map; the default is the dim red of the
  screenshot.
- Pan by dragging empty space or with the middle button, zoom with the
  wheel or a pinch, and a "fit map" button.

Token footprints by Lancer size:

| Size | Hexes |
|---|---|
| 1/2, 1 | 1, drawn smaller for 1/2 |
| 2 | 3, a triangle |
| 3 | 7, a hex and its ring |
| 4 | 12 |
| ? | 1 |

## Step 1. Schema

New file `supabase/battlemap.sql`, safe to run twice like the others.

`battlemaps`: `id`, `name`, `background` (storage path), `grid` (jsonb:
orientation, hex size, offset, line colour and opacity, columns and rows),
`paint` (jsonb, hex key "q,r" to a colour and optional label), `created_by`,
`updated_at`.

`battle_tokens`: `id`, `map_id`, `kind` ('contact', 'custom' or 'prop'),
`contact` (the dossier name, for a contact token), `label`, `color`,
`image` (storage path, overrides the dossier picture), `description`,
`size`, `q`, `r`, `facing`, `scale` (props only), `z`, `updated_by`,
`updated_at`.
A prop's `q`, `r` is its centre hex; its picture is drawn at `scale` and
`facing` with no base.

RLS, following the existing pattern:

- Anyone reads maps and tokens.
- Only the archivist inserts, deletes, or updates maps, and inserts or
  deletes tokens.
- Any signed-in reader updates a token, but a trigger rejects changes to
  anything other than `q`, `r`, `facing`, `label`, `color` and
  `description` unless the caller is the archivist.
- Both tables are added to the `supabase_realtime` publication.

Backgrounds use the existing `archive` bucket and its 1 MB limit: the page
resizes them to a 2400 px long edge as WebP and lowers quality until they
fit, the way `fitImage` does for gallery pictures.

## Step 2. Live sync

Two channels per map over one socket:

- Broadcast `map:<id>` for things that should not touch the database:
  a token mid-drag (sent at most every 50 ms), "token held by" while someone
  is dragging it. Nothing is stored.
- Postgres changes on `battle_tokens` and `battlemaps` for that map, which
  carry the saved result when a drag ends or anything is edited.

Rules:

- Dropping a token writes its new `q`, `r` once. Every client applies the
  row it gets back, so the database is always the truth.
- A token being dragged by someone else shows their name and cannot be
  picked up until they let go, or until 5 seconds pass with no update.
- Two edits to the same token: the later save wins.
- On reconnect or tab focus, the page reloads the map and its tokens in
  full before listening again.
- Socket fails to connect: poll `battle_tokens?map_id=eq.<id>` and the map
  row every 2 seconds, with a small "live link down" notice.

## Step 3. Page

Layout:

- The map fills the window, drawn on one canvas: background, paint, grid,
  then tokens.
- The top left has the map name, a map picker, and "Back to the archive".
- The left side holds the archivist's tool rail: Select, Paint, Erase,
  Background and grid, Add token.
- A side drawer for the selected token: picture, name, colour, size,
  description, and for a contact token a "Open dossier" link and its
  core stats (HP, Armor, Speed, Evasion, E-Defense).
- A token roster that can be collapsed, listing the tokens on the map, so
  one can be found and centred.

Controls:

- Click a token to select it; drag to move it smoothly, and it snaps to
  the nearest hexes when dropped.
- Add prop (archivist): upload or pick a picture, then drag its corner
  handle to scale and its top handle to rotate.
- Paint: pick a colour and a label (for example "Hazard", "Cover"), then
  click or drag across hexes. Erase clears them.
- Add token: search the dossiers by name and drop the result on the map,
  or make a blank token.
- Hover a token for its name and description.
- R rotates the selected token's facing; Delete removes it (archivist).

Archive change: one entry in `INDEXES`,
`{ id: "battle", label: "Battle map", href: "battlemap.html" }`.

Contact data: the map needs each contact's picture, size and core stats. It
loads a snapshot baked into `battlemap.html` by a script like
`tools/chart-contacts.sh` (extended to take every contact, not only the ones
on the chart), then overlays live `contacts` rows as the Star chart does.

## Step 4. Rollout

1. Run `supabase/battlemap.sql` in the SQL editor, then turn on Realtime
   for the two tables if the publication step did not.
2. Build `battlemap.html` with the archivist tools and live sync, tested
   with two browser windows signed in as different accounts.
3. Add the tab to the archive and the snapshot script.
4. Try it on one real encounter before the next session; fix what the table
   finds.

Rough size: about 150 lines of SQL, about 1500 lines for `battlemap.html`,
and 1 line in `index.html`.

## Comments

- 2026-10-11: chose a live shared table over a sandbox, background image
  plus painted hexes for terrain, dossier and blank tokens, and saving to
  the site.
- 2026-10-11: reference screenshots from the Tabletop Simulator table. Top
  down only; smooth drag that snaps on drop; flat-top hexes; props brought
  into the first version for the asteroids and station pieces.
- 2026-10-11: scope cut to a visual planning board. Any signed-in reader
  moves tokens, no owners or hidden tokens, no pings, and backgrounds fit the
  existing 1 MB limit instead of raising it.
