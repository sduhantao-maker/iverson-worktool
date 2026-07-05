#!/bin/zsh
set -eu

TARGET_USER="${1:-}"
if [[ -z "$TARGET_USER" ]]; then
  echo "missing target user" >&2
  exit 64
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_SOURCE="$SCRIPT_DIR/keepgoing-helper"
HELPER_TARGET="/usr/local/bin/keepgoing-helper"
SUDOERS_TARGET="/etc/sudoers.d/keepgoing"
SUDOERS_TEMP="$(/usr/bin/mktemp /tmp/keepgoing-sudoers.XXXXXX)"

if [[ ! -f "$HELPER_SOURCE" ]]; then
  echo "helper source missing: $HELPER_SOURCE" >&2
  exit 66
fi

/usr/bin/install -d -o root -g wheel -m 0755 /usr/local/bin
/usr/bin/install -o root -g wheel -m 0755 "$HELPER_SOURCE" "$HELPER_TARGET"
/bin/rm -f /etc/sudoers.d/clamshell-wifi /usr/local/bin/clamshell-wifi-helper

/bin/cat > "$SUDOERS_TEMP" <<EOF
$TARGET_USER ALL=(root) NOPASSWD: $HELPER_TARGET status, $HELPER_TARGET enable, $HELPER_TARGET disable
EOF

/usr/sbin/visudo -cf "$SUDOERS_TEMP" >/dev/null
/usr/bin/install -o root -g wheel -m 0440 "$SUDOERS_TEMP" "$SUDOERS_TARGET"
/bin/rm -f "$SUDOERS_TEMP"

echo "installed"
