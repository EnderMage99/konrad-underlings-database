# Konrad Underlings Database

Overseer Logs — a scan index of every hostile encountered across the campaign.
LANCER NPC readouts, transcribed out of COMP/CON screenshots and filed by
faction, tier and battlefield role.

**Live site:** https://endermage99.github.io/konrad-underlings-database/

## What's in it

- **Every hostile contact** met so far, filed by faction, with the full stat
  line and every weapon, system, trait and reaction recorded verbatim from
  the scans. The live counts are on the page itself.
- **Two indexes.** The Combat Index holds the Dossiers, the Variants and a
  Stat table that puts every contact side by side. The Record Index holds
  Personnel, Lancers, the Hall of Infamy, the Registry and the Comment log.
- **Horrors** - contacts that carry the Abominable trait, so a scan returns
  nothing but the word. Their dossiers hold "???" for every reading and
  describe only what they were seen doing in combat, with assumed weapons and
  traits marked as such. The section renders in COMP/CON's HORUS glitch
  style, slowed and muted so it does not strobe, and goes still under
  prefers-reduced-motion.
- **Variant families** — contacts that scan almost identically and split on
  only a handful of features, laid out as an aligned comparison computed
  from the stat blocks.
- **A Hall of Infamy** for the contacts that cost the squad something, with
  the account of the engagement the scan itself cannot record.
- **Targetable parts** for a contact big enough to have them, each part with
  its own Health bar, its own separate scan, and its own effect on the body.
- **Visual contact stills** for contacts that have one on file.
- Search by contact name, with a *Search in* switch to look inside weapons,
  systems, traits, reactions or parts instead, plus filters by faction, tier
  and role.
- **Arrival order** - sort contacts by when they were indexed, newest or
  oldest first, and a **NEW** tag on everything from the last three batches
  of additions.

## Viewing it

The whole thing is one self-contained `index.html`. No build step, no
dependencies, no network calls — it runs offline if you download it.

To serve it from GitHub Pages: **Settings → Pages → Source: Deploy from
branch → `main` → `/ (root)`**. The `.nojekyll` file is there to stop Jekyll
from touching anything on the way out.

Without Pages enabled, clicking `index.html` on GitHub shows you the source
rather than the page.

## Updating

The archivist edits in the page. Once `supabase/editing.sql` has run and an
account carries the moderator flag, every dossier grows an **Edit sheet**
button, the Combat Index controls gain **New contact** (blank, or a copy of
any sheet on file), and each personnel file gains **Edit file** with a
**New personnel file** button above the list. Sheets saved this way live in
the `contacts` and `personnel` tables and are merged over the baked data at
load, so a saved sheet replaces the one in the file without the file
changing. Pictures upload to the same Storage bucket as annotation images.
A hidden contact can be restored from the list at the foot of the dossiers.

Everything below still applies to the baked data in `index.html`, which is
the offline copy and the fallback for anything not yet saved through the
page:

- Contact stat blocks are the `DATA` array. A contact scanned in pieces
  carries a `parts` array alongside its weapons and systems; an unread part is
  a named entry with no sheet rather than a gap.
- Variant families are `VARIANT_GROUPS` — the shared / changed / unique split
  is *computed* from the stat blocks, not written by hand, so it can't drift
  out of step with the data.
- The arrival ledger is `ADDED`: one entry per commit that indexed at least
  one new contact, oldest first. It drives the *Sort: Newest / Oldest first*
  chips and the **NEW** tag, which every contact in the last three entries
  wears. A commit that adds no contact gets no entry, so it never ages
  anyone out. When you index a contact, append an entry with the date and
  the contact's full name (or add the name to that day's entry if there
  already is one). A contact left out of the ledger is flagged in the
  browser console.
- Tier scaling lines are `TIER_SCALING`.
- Class briefings are `LORE`, keyed by contact name. A contact with no entry
  just doesn't show the section. Archetypes that appear twice under different
  loadouts (Witch, Hornet) share one string rather than duplicating it.
- Visual contact stills are `VISUALS` at the foot of the script, one keyed
  line each, as data URIs.
- Hall of Infamy records are `INFAMY`. Each one keys a contact by name and
  borrows that contact's still, so the record and the scan cannot drift
  apart; the prose is the part no stat block holds.
- Unit icons are `ICONS`, keyed the same way and sitting beside them. A
  contact with one uses it for its card thumbnail and keeps its still for
  the visual contact panel — icons are small square crops, stills are full
  captures, and the thumbnail frame wants the former.

## Accounts and annotations

Players can log in and file annotations under any dossier, personnel file,
Lancer file or assisting NHP. That part is backed by Supabase, reached over
plain `fetch` so the page stays dependency-free. The publishable key in the
source is meant to be public; every write is gated by row-level security
server-side.

One account can keep as many characters as it likes, each with its own
callsign, title and picture, and switch between them from the account panel.
Annotations are attributed to whichever character is speaking at the time.
The active character is a local choice, so switching costs no round trip.

Any character can open a Lancer file from the account panel. Its owner
writes the file, names its mech and picks which of their characters wrote
each piece; attaches their other characters as assisting NHPs; and pins
in-character comments, each in the voice of one of their characters, above
the annotations. The two baked entries, Star and Nebula, are claimed the same
way by whoever holds a character of that name.

Schema lives in `supabase/`, as migrations to run in the Supabase SQL editor
in this order: `characters.sql`, `moderation.sql`, `files.sql`, `images.sql`,
`editing.sql`, `lancers.sql`.
Each is safe to run twice. The page works either side of every one of them -
it tries the fuller query first and falls back if a table or column is not
there yet, so a feature simply stays hidden until its migration lands.

## A note on the stat blocks

The NPC classes, systems and traits reproduced here are LANCER content and
belong to Massif Press. This is a campaign play aid for the table, not a
substitute for the books. No licence is asserted over that material — if this
repo is going to stay public, worth deciding how you want to handle that.

The visual contact stills are images sourced from elsewhere; check you're
happy publishing them before making the repo public.
