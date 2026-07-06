# Auto Message Sidebar Integration Design

## Goal

Merge Auto Message into the existing KeepGoing macOS app as a second feature area. The app should keep the current KeepGoing screen and behavior intact while adding a BetterDisplay-inspired left sidebar with two navigation items:

- KeepGoing
- Auto Message

Selecting KeepGoing shows the current KeepGoing interface. Selecting Auto Message swaps the right content area to a new Auto Message configuration screen.

## Non-Goals

- Do not rename the app.
- Do not redesign the existing KeepGoing content cards, toolbar behavior, helper checks, or mode-switching logic.
- Do not change the privileged helper, sudoers installer, or `pmset` behavior.
- Do not ship the old standalone AutoMessage Python project inside KeepGoing.

## User Experience

The app opens to KeepGoing by default. The window adds a persistent left sidebar styled after BetterDisplay: light translucent panel, rounded selected rows, blue icons, and macOS traffic-light window controls preserved in the titlebar area.

The sidebar contains only two items. When KeepGoing is selected, the right side contains the existing KeepGoing UI as closely as possible to the current build. When Auto Message is selected, the right side shows message automation controls.

## Layout

The root window becomes a two-column layout:

- Sidebar: fixed width 210 px.
- Content area: fills the remaining width.

The current KeepGoing `MainViewController` should be refactored so its existing toolbar/content layout can live inside the content area rather than owning the entire window root. The visual goal is preservation, not redesign.

## KeepGoing Section

KeepGoing keeps these existing behaviors:

- Refresh button checks status.
- Toolbar shows keep-awake and normal-sleep modes.
- Toggle switch enables/disables keep-awake mode.
- Helper install card and warning card remain.
- Existing helper command execution and status parsing remain unchanged.

## Auto Message Section

The Auto Message section provides:

- Schedule controls for daily hour and minute.
- Target rows for Codex and Claude.
- Per-target app name, process name, message text, and enabled state.
- `Submit after paste` toggle.
- `Dry run` toggle.
- `Test Send` action for running once immediately.
- `Install Schedule` action that writes and loads a user LaunchAgent.
- `Uninstall Schedule` action that unloads and removes that LaunchAgent.
- Status/log area for latest operation result.

The first implementation can support a single daily schedule shared by all targets. Multiple schedules or per-target schedules are out of scope.

## Data Storage

Auto Message settings are stored in the user's Application Support directory:

`~/Library/Application Support/KeepGoing/auto-message.json`

The stored JSON includes:

- schedule hour and minute
- dry-run flag
- submit-after-paste flag
- target list
- last updated timestamp

The app should create defaults on first launch if the file does not exist.

## Automation Engine

Auto Message should use Swift-native implementation in KeepGoing rather than depending on the old Python script.

The send operation should:

1. Activate the configured app by name.
2. Wait for the configured launch delay.
3. Set the clipboard to the configured message.
4. Use System Events AppleScript to focus the process and send Command-V.
5. Optionally send Return if submit is enabled.

The scheduled operation uses a user-level LaunchAgent:

`~/Library/LaunchAgents/com.iverson.keepgoing.automessage.plist`

The LaunchAgent runs a bundled helper executable named `keepgoing-automessage` under the app bundle's `Contents/Resources`. The GUI app owns configuration and install/uninstall actions; the helper only reads the saved settings and performs one send cycle. This keeps scheduled execution reliable without forcing the full GUI to open.

## Permissions

Auto Message requires macOS Accessibility permission for UI scripting. The UI should detect common AppleScript failure cases and show a clear message telling the user to grant Accessibility access to KeepGoing in:

`System Settings -> Privacy & Security -> Accessibility`

The app should not silently fail when Accessibility access is missing.

## Error Handling

Auto Message actions should show concise status text for:

- Missing target app.
- Missing or empty message.
- AppleScript failure.
- Accessibility permission failure.
- LaunchAgent write/load/unload failure.
- Invalid schedule time.

KeepGoing errors should continue to use the existing status and helper error display paths.

## Testing

Verification should include:

- Build succeeds with `./Scripts/build_app.sh`.
- KeepGoing screen still opens by default.
- KeepGoing mode/status refresh still works as before.
- Sidebar switches between KeepGoing and Auto Message.
- Auto Message settings persist across app relaunch.
- Dry-run send does not operate on windows but reports intended actions.
- LaunchAgent plist generation validates with `plutil -lint`.

Real message sending may require manual verification because it depends on app windows and Accessibility permissions.

## Implementation Sequence

1. Add sidebar navigation and content host while preserving current KeepGoing view.
2. Move existing KeepGoing UI into a section view/controller.
3. Add Auto Message model and settings persistence.
4. Build Auto Message UI.
5. Add send-once AppleScript execution.
6. Add LaunchAgent install/uninstall.
7. Update README and screenshots if needed.
8. Build and perform manual checks.
