# Airpisode

*Never miss what's next.*

A native macOS entertainment release tracker. Search TMDB for TV shows and movies, add them to your local library, see upcoming releases on a dashboard, and get local notifications before they air.

## Requirements

- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Setup

```bash
cp Airpisode/TMDBKey.xcconfig.example Airpisode/TMDBKey.xcconfig
# edit TMDBKey.xcconfig and set your TMDB API key
xcodegen generate
open Airpisode.xcodeproj
```

The `.xcodeproj` is generated from `project.yml` and is git-ignored. `TMDBKey.xcconfig` contains your API key and is also git-ignored — never commit it.

## Architecture

- SwiftUI app targeting macOS 13+, no third-party dependencies in the app target
- `TMDBClient` — single async API client behind a protocol (stubbed in tests)
- `LibraryStore` — actor serializing all persistence to JSON in Application Support
- `ReleaseEngine` — refreshes stale titles, detects release-date changes
- `NotificationScheduler` — local notifications with deterministic IDs

This product uses the TMDB API but is not endorsed or certified by TMDB.
