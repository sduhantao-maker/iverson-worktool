# KeepGoing Agent Notes

- This is a local macOS utility project. Keep source under this project root; do not operate from `/Users/iverson`.
- Build with `./Scripts/build_app.sh`; output goes to `dist/KeepGoing.app`.
- Do not commit `dist/`, generated app bundles, caches, logs, or local secrets.
- The helper and sudoers scripts affect `/usr/local/bin/keepgoing-helper` and `/etc/sudoers.d/keepgoing`; do not run installer/uninstaller commands unless the user explicitly asks.
- Before Git work, verify `git rev-parse --show-toplevel` returns `/Users/iverson/Code/keepgoing`.
