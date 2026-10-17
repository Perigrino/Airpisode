# Contributing

Thanks for your interest in Airpisode. This guide covers how to set up the project, the conventions the codebase follows, and how to send a change.

## Getting set up

Follow the setup steps in the [README](README.md) to get a working build with your own TMDB API key.

## Ground rules

- Keep the app local-only. Airpisode has no backend, accounts, or sync.
- Never commit `Airpisode/TMDBKey.xcconfig` or any API key.
- Keep the app target free of third-party dependencies.
- Add a test for every behavior change.

## Conventions

- **Commits**: short, imperative subjects. Prefix with `feat:`, `fix:`, `docs:`, or `chore:`.
- **Code**: match the surrounding style, and keep one responsibility per file.
- **Tests**: put them in `AirpisodeTests` and stub the network with `StubTMDBClient`.

## Sending a change

1. Create a branch.
2. Make your change and run the tests:

```bash
xcodegen generate
xcodebuild test -project Airpisode.xcodeproj -scheme Airpisode -destination 'platform=macOS'
```

3. Open a pull request describing what changed and why.

## Reporting a bug

Open an issue with what you expected, what happened, and the steps to reproduce it. Include your macOS version.
