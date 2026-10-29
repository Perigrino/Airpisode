# Airpisode — BAMA audit

Date: 2026-10-28 · Baseline: `181 tests pass` · Build: Release from `project.yml`

## Verdict

The data layer is in good shape: services are separable, the library is pure-value,
181 tests cover release logic, notifications, migrations, and queries. The weak layer is
the **presentation shell** and the **failure paths around it**.

## P0 — shell and discoverability

1. **Fixed portrait window.** `WindowMetrics` pins 720×1180, removes `.resizable`,
   and `PortraitWindow` re-pins on every attach. On a 3440×1410 display the app is a
   tall phone column. Resizing, Split View, and full screen are all disabled by hand.
2. **Hover-only bottom dock.** Navigation is invisible until the pointer reaches the
   bottom 100 pt. There is no sidebar, no View menu, and no ⌘1…⌘5. A first-time user
   cannot see where they can go.
3. **Forced dark mode.** `.preferredColorScheme(.dark)` on every scene; the light-mode
   palette does not exist. `Theme.background` is `NSColor.black` and `Theme.card` is
   `Color.white.opacity(0.05)` — both break in light mode.
4. **No keyboard path.** Refresh is toolbar-only, search lives on one page, no command
   for navigation, no menu-bar equivalents.
5. **iOS type scale.** Page titles are 26 pt bold; body copy is `.subheadline` (11 pt on
   macOS). The HIG body size is 13 pt.
6. **Hidden scrollbars.** `PortraitWindow` disables scrollers and zeroes their alpha on
   every layout pass and every live-scroll notification. This fights the system setting.

## P1 — page UX

7. **My Shows / My Movies ignore their own query API.** `Library.queryShows` and
   `queryMovies` (search, filter, sort) are implemented and tested but the views sort by
   name only. No search field, no filter, no sort menu.
8. **Rows repeat static chrome.** Every row carries a "TV Show"/"Movie" chip the page
   already states, a 76×114 poster, and a tiny chevron. At 720 wide that is fine; in a
   resizable window it wastes vertical space.
9. **Aired rows are hidden in a card.** The most actionable item ("you have 4 unwatched
   episodes") is buried under three release sections, and its mark-watched button is an
   unlabeled 16 pt glyph.
10. **No error recovery.** `lastRefreshError` is a passive orange label. There is no
    Retry, no last-updated time, and no offline explanation.
11. **No destructive undo.** Remove is immediate from a context menu; only the diary has
    an undo affordance.
12. **Empty states are decorative.** They name the problem but the primary button is a
    full-width `borderedProminent` tinted purple, off the Mac pattern.

## P2 — robustness

13. **A corrupt `library.json` is silently replaced by an empty `Library()`** and the
    next save overwrites the user's file. `LibraryStore.load` swallows every error.
14. **Save errors are swallowed** at every call site (`try? await store.save`). A full
    disk or a permissions change is invisible.
15. **Saves are fire-and-forget Tasks.** Mutations create independent save tasks; the
    actor serialises writes but not their order, so an older snapshot can land last.
16. **No network retry.** `TMDBClient` performs one request, maps 401/404 and nothing
    else. A 429, a 503, or a dropped connection fails the whole refresh.
17. **Sequential refresh.** `ReleaseEngine` fetches titles and seasons one at a time.
    Nine shows means nine round trips before the spinner clears.
18. **Refresh has no progress.** `isRefreshing` is a boolean; a long pass looks stalled.

## What stays

- `Library`, `Library+*`, `ReleaseEngine`, `NotificationPlanner`, `ScheduleChangeRecorder`
  and their tests.
- The inline expandable detail (`TitleDetailContent`) and poster-tinted cards as a
  signature, dialled down.
- Menu bar extra, notification actions, and the background sweep.
- JSON-only, account-free, offline-first storage.

## Target state

A native sidebar window (resizable, light and dark, 880×620 minimum) where every
destination is visible, every frequent action has a menu item and a shortcut, lists can
be searched, filtered and sorted, and every failure has a recovery path. See
`docs/DESIGN.md` and `docs/STORIES.md`.
