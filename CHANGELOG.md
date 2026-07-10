# Changelog

## Unreleased

## v0.4.2

- Updated Codex Auto Message delivery for ChatGPT desktop app (Codex mode).
- Existing `Codex` configurations now launch bundle ID `com.openai.codex` and target the `ChatGPT` process without reconfiguration.

## v0.4.1

- Fixed paste shortcuts in app text fields by adding the standard macOS Edit menu.
- Message fields now support `Cmd+V`, `Cmd+C`, `Cmd+X`, and `Cmd+A`.

## v0.4.0

- Changed Auto Message file handling to attach original files instead of expanding file contents into text.
- Kept support for multiple selected files per target.

## v0.3.0

- Added multi-file support to Auto Message.
- Added file selection UI for Codex and Claude rows.

## v0.2.0

- Added Auto Message.
- Added daily scheduled sends through a macOS LaunchAgent.
- Added date and time selection.
- Added dry run and submit-after-paste options.

## v0.1.0

- Added the native macOS app shell.
- Added KeepGoing for local keep-awake behavior.
