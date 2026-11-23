# Changelog

## Unreleased

### KeepGoing
- `disable` now restores the sleep settings you had before `enable`, per power source, instead of writing `sleep 1`.
- KeepGoing switches itself off at a set time (default 08:00) and on low battery (default 20%), through a user LaunchAgent that keeps working after the app quits.
- The app detects an out-of-date installed helper and offers to update it.
- The installer no longer re-owns an existing `/usr/local/bin` (it broke Homebrew on Intel Macs).
- The KeepGoing / Sleep toolbar choices are now clickable.

### Auto Message
- Each target is sent on its own: a failing app no longer stops the others.
- Edits are saved automatically; changing the time moves an installed schedule. The schedule card shows the installed time.
- A scheduled run that starts more than 30 minutes late is skipped, so a missed 02:00 send no longer fires when the Mac wakes.
- A run with the screen locked fails instead of typing into the lock screen. Scheduled runs no longer raise a permission prompt.
- Test Send runs in the background instead of freezing the window, and the clipboard is restored after a send.
- Log lines carry a timestamp and an outcome tag.

### App
- Glass controls with spring motion: switches, buttons, a gooey selection indicator.
- Full Dark Mode; the sidebar uses the system sidebar material.
- Universal build (arm64 + x86_64) with an explicit macOS 13 deployment target. Earlier builds ran only on Apple silicon with the build machine's macOS version.
- `runCommand` drains pipes while the child runs and has a timeout.
- Tests cover the runner, the auto-off guard, and the helper's snapshot and restore.

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
