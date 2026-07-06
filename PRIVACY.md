# Privacy

Iverson’s WorkTool is designed as a local macOS utility.

## Data Collection

The app does not collect analytics, telemetry, crash reports, usage metrics, or personal data.

## Network Access

The app does not upload messages, files, prompts, or settings to a remote server.

## Local Storage

Auto Message settings are stored locally:

```text
~/Library/Application Support/KeepGoing/auto-message.json
```

Scheduled task logs are stored locally:

```text
~/Library/Application Support/KeepGoing/Logs/
```

The scheduled LaunchAgent is stored locally:

```text
~/Library/LaunchAgents/com.iverson.keepgoing.automessage.plist
```

## File Attachments

When you select files in Auto Message, the app stores local file paths in its settings file.

When sending, selected files are written to the macOS pasteboard as file URLs so the target app can receive them as attachments. The app does not expand files into message text and does not upload file contents itself.

## Accessibility Permission

Accessibility permission is used for local UI automation:

- activate the target app
- focus the chat input
- paste message text
- paste file attachments
- press Return when requested

You can revoke this permission at any time in:

```text
System Settings -> Privacy & Security -> Accessibility
```

## Uninstalling Scheduled Sends

Use the `Uninstall` button in Auto Message to unload and remove the LaunchAgent. You can also remove:

```text
~/Library/LaunchAgents/com.iverson.keepgoing.automessage.plist
```

After the LaunchAgent is removed, scheduled sends should stop.
