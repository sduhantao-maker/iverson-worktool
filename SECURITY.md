# Security

Iverson’s WorkTool controls local macOS UI and power settings. Treat it like any other automation tool that receives Accessibility permission.

## Permission Model

The app may ask for:

- Accessibility access, for UI automation
- administrator approval, for installing the KeepGoing helper

The Auto Message helper is located inside the app bundle:

```text
Iverson’s WorkTool.app/Contents/Resources/keepgoing-automessage
```

The KeepGoing helper is installed to:

```text
/usr/local/bin/keepgoing-helper
```

## Recommendations

- Only grant Accessibility permission to builds you trust.
- Prefer building from source if you are reviewing the code.
- Do not run modified forks with Accessibility permission unless you understand the changes.
- Keep `Dry run` enabled while testing Auto Message.
- Remove the scheduled LaunchAgent if you no longer need scheduled sends.

## Reporting Security Issues

If you find a security issue, please open a GitHub issue with a minimal reproduction and mark it clearly as security-related.

Avoid posting private files, tokens, local paths, or personal prompts in public issues.
