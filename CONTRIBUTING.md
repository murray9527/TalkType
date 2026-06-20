# Contributing to TalkType

Thanks for your interest in contributing!

## How to contribute

1. **Bug report or feature request** — open a [GitHub Issue](https://github.com/YOUR_ACCOUNT/TalkType/issues/new)
2. **Code contribution** — fork the repo, create a branch, open a Pull Request

## Pull request process

- Keep changes focused. One PR = one concern.
- Run `swift build` before submitting to make sure it compiles.
- If adding a new feature, consider whether it fits the project's scope (privacy-first local voice input for macOS).
- For UI changes, include a screenshot if possible.

## Code style

- The project uses Swift 6 with strict concurrency checking.
- Follow the existing code style — match comment density, naming, and idioms of the surrounding code.
- Use `print("[ModuleName] message")` for debug logging (not `os_log` or `NSLog`).

## Development setup

```bash
swift build
swift run
swift test
```

## Questions?

Open a Discussion or an Issue — we're friendly.
