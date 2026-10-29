# Airpisode — BAMA final report

Date: 2026-10-29 · Path: review → design → rebuild → verify

## 1. Review

`docs/AUDIT.md` (2026-10-28, baseline 181 tests / Release build) concluded the data layer
(`Library`, release engines, notification planner, schedule recorder) was sound, and the
weakest layers were the presentation shell and the failure paths around it.

**P0 — shell and discoverability (6 findings).** Fixed portrait window; hover-only dock;
forced dark mode; no keyboard path; iOS type scale; hidden scrollbars.

**P1 — page UX (5 findings).** Lists ignored their own query API; rows repeated static
chrome; aired items buried; passive error handling; decorative empty states.

**P2 — robustness (7 findings).** Corrupt library replaced silently; saves swallowed;
fire-and-forget save ordering; no network retry; sequential refresh; no progress.

## 2. Design

`docs/DESIGN.md` fixed the target: a sidebar window + menu bar extra, two levels maximum,
command map (⌘1–⌘5, ⌘R, ⌘N → Discover, ⌘, settings, ⌘F search), design tokens (light canvas
`#F5F5F7`, card `#FFFFFF`, accent fill `#6D3FD1` / `#7C5CE0`, spacing 4 pt grid, radii 8/12/16,
system text styles only, Silk motion seed without hover scale), flat surfaces without glass,
empty and failure states specified per page.

## 3. Rebuild — findings closed

| Audit finding | Fix shipped |
| --- | --- |
| P0-1 fixed portrait window | `NavigationSplitView` sidebar shell; `RootView` frame `minWidth: 880, idealWidth: 1120, maxWidth: .infinity` / `minHeight: 620, idealHeight: 760, maxHeight: .infinity`; `.windowResizability(.contentMinSize)`; `.defaultSize(width: 1120, height: 760)` |
| P0-2 hover-only dock | New `SidebarView` (`Features/Navigation/SidebarView.swift`); `SidebarCommands` + `ToolbarCommands`; Go menu ⌘1–⌘5, View/⌘R, File/⌘N → Discover, App/⌘, |
| P0-3 forced dark | Rewritten adaptive `Theme` (`Support/Theme.swift`); `AccentColor` asset (`light #6D3FD1`, `dark #7C5CE0`); light + dark palettes |
| P0-4 no keyboard path | App commands (`AirpisodeApp.swift`): sidebar ⌘1–⌘5, refresh ⌘R, discover ⌘N, settings ⌘, |
| P0-5 iOS type scale | System text styles only; Chip icon + CountdownBadge unit raised from 9 pt to 10 pt (HIG floor) |
| P0-6 hidden scrollbars | `.scrollIndicators(.hidden)` removed from content scrolls; system scrollbars |
| P1-7 lists ignored query API | `MyShowsView` / `MyMoviesView` gained searchable, filterable, sortable lists with `EmptyState` first actions |
| P1-8 row chrome | `TitleRowView` density (44×64 poster, tighter spacing), `SearchRowView` (headline, chip, year, rating, 2-line overview, chevron) |
| P1-9 buried aired items | Next-up labels; `nextLabel` returns `tvStatus` for Ended/Canceled shows |
| P1-10/11 failure UX | `InlineBanner` with Retry + last-refreshed time; save errors surfaced (`AppState.storageError`), library notice, corrupt-file banner |
| P1-12 empty states | First action wired on every empty/filtered-to-empty state (Discover → Find something to track; Shows/Movies → Find shows/movies; Diary → Go to To Watch; clear-filters state) |
| P2-13 corrupt file | `LibraryStore`: last-good backup, `library.corrupt-<timestamp>.json` preservation, missing-primary fallback |
| P2-14/15 save failure + ordering | Save sequence guard + `saveNow()` awaited saves; `AppState.storageError` / `libraryNotice` surfaced |
| P2-16 network retry | `TMDBClient` retry with backoff for 429 / 5xx / transient `URLError` |
| P2-17/18 refresh sequencing | Refresh launch/alert paths; per-refresh progress surfaced via last-refresh tracking |

**Bugs found during screenshot review and fixed before final verification:**

1. **Movie release times.** TMDB sends date-only releases as `…T00:00:00.000Z`; the mapper
   treated midnight as a timed release, so rows showed “1 Dec, 12:00 am”. Now treated as
   date-only (`hasTime == false`) via UTC hour/minute/second inspection; covered by
   `testMovieReleaseTreatsMidnightAsDateOnly`.
2. **Window auto-resizing on section switch.** `ScrollView` reported content height as its
   ideal size and the WindowGroup resized. Fixed with an explicit frame including ideal
   sizes; verified stable at 1120×760.
3. **Brand accent.** Global `AccentColor` asset (`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor`) + `.tint(Theme.accentFill)`.
4. **9 pt text.** Chip icon and countdown unit raised to 10 pt (HIG floor).
5. **Ended shows.** Rows now show the status (“Ended”) instead of “No upcoming episode”.

## 4. Verify

- **Tests:** `xcodebuild … test` → **197 tests, 0 failures** (baseline 181 + 17 new:
  `DateTextTests` 13 wording tests; `LibraryStoreTests` 9 recovery/backup/sequence/save-error
  tests; `TMDBMapperTests` date-only coverage).
- **Build:** Debug and **Release** → **BUILD SUCCEEDED**.
- **Screenshots:** `build/shots/` — dark: dashboard, shows, movies, diary, discover,
  detail, no-results, settings (general/about), menu bar; light: dashboard, shows, movies,
  diary, discover, settings (general/notifications/about). `Screenshots/` mirrors the light set.

## 5. Shipped surface (summary)

- One resizable window (1120×760 default, 880×620 min), sidebar (180–280 pt), unified
  toolbar, light + dark, system scrollbars, system text styles, one accent.
- Sections: To Watch / Shows / Movies / Diary / Discover; Go menu ⌘1–⌘5, refresh ⌘R,
  discover ⌘N, settings ⌘,.
- Discover: recommendations + TMDB search with skeletons, inline error banner, expandable
  rows (overview + rating + chevron).
- Diary: stats card, date groups, undo.
- Settings: 3 tabs (General / Notifications / About), no initial focus, AppKit key field,
  library-folder reveal, send test alert.
- Menu bar extra: 5 upcoming rows, one-tap mark watched, Open/Refresh footer.
- Window reopen after close: `MainWindowKeeper` + `WindowKeeperInstaller` restore the single
  library window (Dock click, notification tap, menu-bar Open all bring it back).

## 6. Follow-ups

- App icon legibility in About (56 pt tile) — resolved: the flat placeholder PNGs were
  replaced by `Airpisode/Icon/AppIcon.icon` (Icon Composer, V4 "Queue of three": three
  translucent discs + white play triangle), compiled by Xcode into `Assets.car` +
  `AppIcon.icns`, verified in Default / Dark / TintedDark / ClearLight down to 16 pt.
  `tools/make_icon.sh` and `tools/icon_review.sh` are in the repo for re-renders.
- Settings Notifications pane at 620 pt height scrolls at the bottom.
- Refresh still serial per title; consider bounded concurrency (P2-17 partially closed via
  launch/alert paths).
