# Konrad Underlings Database

Overseer Logs — a scan index of every hostile encountered across the campaign.
LANCER NPC readouts, transcribed out of COMP/CON screenshots and filed by
faction, tier and battlefield role.

**Live site:** https://endermage99.github.io/konrad-underlings-database/

## What's in it

- **28 contacts** across four factions — Gongsi (20), Stormrider (3),
  Wildlife (3), Unaligned (2).
- Full stat lines plus every weapon, system, trait and reaction, recorded
  verbatim from the scans.
- **Three views** — Dossiers, Variants, and a Stat table that puts all 28
  side by side.
- **Six variant families** — contacts that scan almost identically and split
  on only a handful of features, laid out as an aligned comparison. Witch and
  Hornet differ on *zero* of sixteen stats.
- **Visual contact stills** for contacts that have one on file.
- Search across every rules string, plus filters by faction, tier and role.

## Viewing it

The whole thing is one self-contained `index.html`. No build step, no
dependencies, no network calls — it runs offline if you download it.

To serve it from GitHub Pages: **Settings → Pages → Source: Deploy from
branch → `main` → `/ (root)`**. The `.nojekyll` file is there to stop Jekyll
from touching anything on the way out.

Without Pages enabled, clicking `index.html` on GitHub shows you the source
rather than the page.

## Updating

Replace `index.html` and commit. Everything lives in that one file:

- Contact stat blocks are the `DATA` array.
- Variant families are `VARIANT_GROUPS` — the shared / changed / unique split
  is *computed* from the stat blocks, not written by hand, so it can't drift
  out of step with the data.
- Tier scaling lines are `TIER_SCALING`.
- Class briefings are `LORE`, keyed by contact name. A contact with no entry
  just doesn't show the section. Archetypes that appear twice under different
  loadouts (Witch, Hornet) share one string rather than duplicating it.
- Visual contact stills are `VISUALS` at the foot of the script, one keyed
  line each, as data URIs.

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

Schema lives in `supabase/characters.sql`. Run it in the Supabase SQL editor;
it is safe to run twice. The page works either side of that migration - it
tries the character-aware query first and falls back to account-level
attribution if the table is not there yet.

## A note on the stat blocks

The NPC classes, systems and traits reproduced here are LANCER content and
belong to Massif Press. This is a campaign play aid for the table, not a
substitute for the books. No licence is asserted over that material — if this
repo is going to stay public, worth deciding how you want to handle that.

The visual contact stills are images sourced from elsewhere; check you're
happy publishing them before making the repo public.
