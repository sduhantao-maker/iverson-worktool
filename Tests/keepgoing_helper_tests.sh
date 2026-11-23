#!/bin/zsh
# Runs keepgoing-helper against a fake pmset, so no real power setting changes.
# usage: keepgoing_helper_tests.sh <path to Resources/keepgoing-helper>
set -eu

HELPER_SOURCE="$1"
WORK="$(/usr/bin/mktemp -d /tmp/keepgoing-helper-tests.XXXXXX)"
trap '/bin/rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL keepgoing-helper: $1" >&2
  exit 1
}

# The fake pmset: `-g` reports SleepDisabled from a state file, `-g custom` prints fixed
# per-source values, and every other call is logged. disablesleep updates the state.
/bin/cat > "$WORK/pmset" <<'FAKE'
#!/bin/zsh
STATE_DIR="${0:h}"
if [[ "$1" == "-g" && "${2:-}" == "custom" ]]; then
  /bin/cat <<'CUSTOM'
Battery Power:
 standby              1
 sleep                5
 womp                 0
 tcpkeepalive         1
 displaysleep         2
AC Power:
 standby              1
 sleep                0
 womp                 1
 tcpkeepalive         1
 displaysleep         10
CUSTOM
  exit 0
fi
if [[ "$1" == "-g" ]]; then
  printf 'System-wide power settings:\n SleepDisabled\t\t%s\n' "$(/bin/cat "$STATE_DIR/sleepdisabled")"
  exit 0
fi
echo "$*" >> "$STATE_DIR/calls.log"
if [[ "$1" == "-a" && "$2" == "disablesleep" ]]; then
  echo "$3" > "$STATE_DIR/sleepdisabled"
fi
FAKE
/bin/chmod 755 "$WORK/pmset"
echo 0 > "$WORK/sleepdisabled"
: > "$WORK/calls.log"

# The helper under test, pointed at the fake pmset and a private snapshot folder.
/usr/bin/sed \
  -e "s#^PMSET=.*#PMSET=\"$WORK/pmset\"#" \
  -e "s#^SNAPSHOT_DIR=.*#SNAPSHOT_DIR=\"$WORK/snapshot\"#" \
  "$HELPER_SOURCE" > "$WORK/helper"
/bin/chmod 755 "$WORK/helper"
SNAPSHOT="$WORK/snapshot/pmset-snapshot"

[[ "$("$WORK/helper" status)" == "normal" ]] || fail "status before enable"

# enable saves the original per-source values once.
"$WORK/helper" enable >/dev/null
[[ "$("$WORK/helper" status)" == "enabled" ]] || fail "status after enable"
expected=$'-b sleep 5\n-b womp 0\n-b tcpkeepalive 1\n-c sleep 0\n-c womp 1\n-c tcpkeepalive 1'
[[ "$(/bin/cat "$SNAPSHOT")" == "$expected" ]] || fail "snapshot content: $(/bin/cat "$SNAPSHOT")"

echo "-b sleep 7" >> "$SNAPSHOT"
"$WORK/helper" enable >/dev/null
[[ "$(/usr/bin/tail -1 "$SNAPSHOT")" == "-b sleep 7" ]] || fail "a second enable must keep the first snapshot"

# disable puts every saved value back, then removes the snapshot.
: > "$WORK/calls.log"
"$WORK/helper" disable >/dev/null
expected=$'-a disablesleep 0\n-b sleep 5\n-b womp 0\n-b tcpkeepalive 1\n-c sleep 0\n-c womp 1\n-c tcpkeepalive 1\n-b sleep 7'
[[ "$(/bin/cat "$WORK/calls.log")" == "$expected" ]] || fail "disable restores the snapshot: $(/bin/cat "$WORK/calls.log")"
[[ ! -e "$SNAPSHOT" ]] || fail "the snapshot is removed after a restore"
[[ "$("$WORK/helper" status)" == "normal" ]] || fail "status after disable"

# KeepGoing already on from an older helper: no snapshot, and disable falls back to sleep 1.
echo 1 > "$WORK/sleepdisabled"
"$WORK/helper" enable >/dev/null
[[ ! -e "$SNAPSHOT" ]] || fail "no snapshot of values that KeepGoing already changed"
: > "$WORK/calls.log"
"$WORK/helper" disable >/dev/null
[[ "$(/bin/cat "$WORK/calls.log")" == $'-a disablesleep 0\n-a sleep 1' ]] || fail "legacy fallback: $(/bin/cat "$WORK/calls.log")"

# Only known keys with whole-number values are restored.
/bin/mkdir -p "$WORK/snapshot"
printf '%s\n' '-b sleep 3' '-b displaysleep 0' '-c sleep 1;rm' '-x sleep 1' '-c womp abc' > "$SNAPSHOT"
: > "$WORK/calls.log"
"$WORK/helper" disable >/dev/null
[[ "$(/bin/cat "$WORK/calls.log")" == $'-a disablesleep 0\n-b sleep 3' ]] || fail "unexpected restore lines: $(/bin/cat "$WORK/calls.log")"

if "$WORK/helper" bogus 2>/dev/null; then
  fail "an unknown command must fail"
fi

echo "keepgoing-helper: all checks passed"
