# KeepGoing

KeepGoing is a local macOS utility for switching the computer between normal sleep behavior and a "keep running" mode.

It builds a small Cocoa app and uses a privileged helper at `/usr/local/bin/keepgoing-helper` to call `pmset`.

## Layout

- `Sources/` - Swift Cocoa app source.
- `Resources/` - app icon, icon source, helper, install/uninstall scripts.
- `Scripts/build_app.sh` - builds and signs `dist/KeepGoing.app`.
- `docs/screenshots/` - UI screenshots from the original Codex build.
- `dist/` - local build output. This directory is ignored by Git.

## Build

```bash
./Scripts/build_app.sh
```

Output:

```text
dist/KeepGoing.app
```

## Helper

The app expects:

```text
/usr/local/bin/keepgoing-helper
```

The bundled installer script installs the helper and a sudoers rule for passwordless helper calls:

```text
/etc/sudoers.d/keepgoing
```

Helper commands:

```bash
keepgoing-helper status
keepgoing-helper enable
keepgoing-helper disable
```

`enable` sets:

```bash
pmset -a disablesleep 1
pmset -a sleep 0
pmset -a tcpkeepalive 1
pmset -a womp 1
```

`disable` sets:

```bash
pmset -a disablesleep 0
pmset -a sleep 1
```

## Git

Track source and docs. Do not track generated app bundles, caches, or local machine state.
