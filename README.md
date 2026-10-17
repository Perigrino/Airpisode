# Airpisode

Never miss what's next.

Airpisode is a macOS app that tracks when your TV shows and movies come out. Search TMDB, add titles to a local watchlist, and see what's airing on a dashboard with countdowns. Airpisode notifies you before a release, using your Mac's notification system. Everything stays on your machine: no account, no server, no sync.

## Features

- **Upcoming dashboard**: groups tracked releases into Today, This Week, and Later, each with a countdown.
- **Watchlist**: tracks any number of TV shows and movies, with next-episode or next-release info on each row.
- **Episode tracking**: browses seasons and episodes for a show, with a status dot for what has aired.
- **Release dates**: shows theatrical, digital, physical, and TV windows for a movie by region.
- **Search and recommendations**: searches TMDB and suggests titles based on what you track.
- **Notifications**: sends an alert before an episode or release, with a lead time you choose.
- **Offline library**: stores your watchlist as JSON on disk, so it loads without a network connection.

## Install

Airpisode ships as a disk image. Download the latest `Airpisode-<version>.dmg`, open it, and drag Airpisode to your Applications folder. The build is not notarized, so on first launch macOS may warn about an unidentified developer: right-click Airpisode and choose Open.

The distributed app ships without an API key. On first launch Airpisode asks for your own free TMDB key and saves it on your Mac. You can change it any time in Settings. Without a key, search and refresh cannot reach TMDB.

Get a key from [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api).

## How it works

Airpisode has no backend. It reads metadata from the TMDB API and keeps your library in Application Support.

- **TMDBClient**: one async client for the TMDB API, behind a protocol so tests run without the network.
- **LibraryStore**: an actor that serializes your library to JSON and writes it atomically.
- **ReleaseEngine**: refreshes stale titles on a schedule and detects when a release date changes.
- **NotificationScheduler**: schedules local notifications with deterministic IDs, so rescheduling never duplicates an alert.

Airpisode never invents a release time. When TMDB lists a date without a time, the app shows the day only and skips time-based alerts.

## Requirements

- macOS 13 or later
- A TMDB API key from [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api)

To build from source you also need Xcode 15 or later and XcodeGen (`brew install xcodegen`).

## Build and run

1. Copy the example config and add your TMDB API key:

```bash
cp Airpisode/TMDBKey.xcconfig.example Airpisode/TMDBKey.xcconfig
```

2. Generate the Xcode project and open it:

```bash
xcodegen generate
open Airpisode.xcodeproj
```

3. Run the app with ⌘R.

The `.xcodeproj` is generated from `project.yml`, so it isn't tracked. `TMDBKey.xcconfig` holds your key and isn't tracked either. Never commit it. The key in this file is a developer fallback; the key a user enters in Settings takes precedence.

## Development

Build and test from the command line:

```bash
xcodegen generate
xcodebuild test -project Airpisode.xcodeproj -scheme Airpisode -destination 'platform=macOS'
```

Build a distributable disk image, with no key baked in:

```bash
./Scripts/build-dmg.sh
```

The image is written to `dist/`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for conventions.

## Data and privacy

Airpisode stores your library at `~/Library/Application Support/Airpisode/library.json` and your TMDB key in your app preferences. It sends your key and search terms to TMDB only. There is no analytics and no telemetry.

## Attribution

This product uses the TMDB API but is not endorsed or certified by TMDB.

## License

[MIT](LICENSE)
