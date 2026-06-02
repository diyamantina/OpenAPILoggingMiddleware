# Contributing

Thanks for your interest in improving OpenAPILoggingMiddleware. This is a
small, focused package, so contributions that keep it that way are the easiest
to merge.

## Before you start

- For anything beyond a typo or an obvious fix, open an issue first so we can
  agree on the approach. See the issue templates under **New issue**.
- By contributing you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Development setup

Requires Swift 6.0+ (Xcode 16+ on Apple platforms, the Swift 6.0 toolchain on
Linux).

```sh
git clone https://github.com/mihaelamj/OpenAPILoggingMiddleware
cd OpenAPILoggingMiddleware
swift build
swift test
```

The suite runs on both macOS and Linux. If you touch platform-conditional code
(`OSLogHandler`, the `StateLock` fallback, file paths), check that it still
builds on the other platform; CI runs the Linux and Apple matrices on every PR.

## Making a change

1. Branch off `main`: `git checkout -b <type>/<short-description>`.
2. Keep the change scoped to one concern.
3. Add or update tests. New behaviour without a test will not be merged.
4. Update `CHANGELOG.md` under an `## [Unreleased]` heading for anything
   user-facing, and update the README if you change a public surface.
5. Run the full suite and confirm it passes before opening the PR.

## Style

- 4-space indentation, trailing commas, no force-unwrapping in library code.
- Inject collaborators through initialisers; avoid global/shared state.
- Match the conventions already in the surrounding files.

## Commits

Use `<type>(<scope>): summary`, for example `fix(redaction): cover Set-Cookie`.
Squash fixups locally before opening the PR. Keep the history readable.

## Pull requests

Fill in the PR template, link the issue it closes, and make sure CI is green.
Smaller PRs get reviewed faster.
