# Airpisode — design plan

## Archetype

**Sidebar window + menu bar extra.** One library window with five destinations, one
quick status surface in the menu bar, one Settings window. The window is resizable and
follows the system appearance.

## Information architecture

```
Library
  To Watch   — everything that needs attention, aired first, then upcoming
  Shows      — tracked series, searchable / filterable / sortable
  Movies     — tracked films, searchable / filterable / sortable
  Diary      — last 7 days of watches, plus lifetime stats
Discover     — search TMDB, recommendations from the library
```

Two levels maximum. Expanding a row reveals detail in place; there is no third column.

## Command map

| Action | Where | Shortcut |
| --- | --- | --- |
| To Watch | sidebar, Go menu | ⌘1 |
| Shows | sidebar, Go menu | ⌘2 |
| Movies | sidebar, Go menu | ⌘3 |
| Diary | sidebar, Go menu | ⌘4 |
| Discover | sidebar, Go menu | ⌘5 |
| Refresh releases | To Watch toolbar, View menu | ⌘R |
| Search current list | toolbar search field | ⌘F |
| Add a title | Shows/Movies toolbar, File menu | ⌘N → Discover |
| Settings | app menu | ⌘, |
| Toggle sidebar | View menu | ⌃⌘S |
| Mark watched / unwatched | row, context menu | — |
| Pin / mute / remove | context menu | — |

## Design tokens

| Token | Light | Dark |
| --- | --- | --- |
| canvas | `#F5F5F7` | `#0E0E11` |
| card | `#FFFFFF` | `#1C1C21` |
| chip | black 6% | white 8% |
| hairline | black 9% | white 9% |
| accent (text/controls) | `#5B34C4` | `#B49CFF` |
| accent fill | `#6D3FD1` | `#7C5CE0` |
| on accent | white | white |

Spacing: 4 pt grid (`4 / 8 / 12 / 16 / 20 / 28`). Window margin 20 pt, card gap 12 pt.
Radii: 8 (chips, posters), 12 (rows, buttons), 16 (cards).
Type: system text styles only. Page title `.title2` semibold, section header `.headline`,
body `.body` (13 pt), metadata `.caption` (11 pt) minimum. No 26 pt display type.

Motion: keep the Silk spring seed, but only for expansion and selection. No hover scale.

## Surface rules

- The sidebar, toolbar, search field, menus and Settings are standard AppKit/SwiftUI.
- Content never gets glass. Cards are flat surfaces with a 1 pt hairline.
- The poster tint remains, at ≤ 10% opacity in dark and ≤ 6% in light.
- Accent is used for selection, countdown numbers, and one primary action per page.
- Status always pairs color with a symbol or a word.

## Empty states

| Page | First run | Filtered to nothing |
| --- | --- | --- |
| To Watch | "Nothing to watch yet" + **Find something to track** → Discover | — |
| Shows | "No shows yet" + **Find shows** → Discover | "No shows match" + **Clear filters** |
| Movies | "No movies yet" + **Find movies** → Discover | "No movies match" + **Clear filters** |
| Diary | "Your diary is empty" + **Go to To Watch** | "No matches" + **Clear filters** |
| Discover | search prompt + recommendations, or "Search for a show or movie" | "No results" + **Clear search** |

## Failure states

- Refresh failure: inline banner with the reason, **Try Again**, and last successful
  update time. It never covers content.
- Save failure: a persistent banner naming the cause; the in-memory library stays usable.
- Corrupt library file: the file is preserved as `library.corrupt-<timestamp>.json`,
  the newest backup is loaded, and a banner explains what happened.
- Missing key: the Welcome sheet, as today.

## Feeling

**Calm anticipation.** The app answers "what is next, and is anything waiting for me?"
in one screen, then gets out of the way. Motion is quiet; numbers are legible; nothing
flashes or scales on hover.
