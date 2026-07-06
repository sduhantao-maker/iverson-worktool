# Contributing

Thanks for considering a contribution.

This project is intentionally small. The goal is a reliable local macOS workflow tool, not a broad automation platform.

## Development

Run tests:

```bash
./Scripts/run_tests.sh
```

Build the app:

```bash
./Scripts/build_app.sh
```

## Pull Requests

Good pull requests usually do one thing:

- fix a specific bug
- improve a specific part of the UI
- add a focused workflow option
- improve docs or install instructions

Please include:

- what changed
- why it changed
- how you tested it

## Boundaries

Please avoid:

- adding cloud services
- adding telemetry
- broad rewrites without a clear user-facing benefit
- changing permissions without documenting why

## Code Style

- Keep the app native and simple.
- Prefer AppKit and existing local patterns.
- Keep UI dense, calm, and utility-focused.
- Avoid unrelated refactors in feature PRs.
