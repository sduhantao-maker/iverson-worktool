#!/bin/zsh
set -eu

# Turn KeepGoing off first, so the saved sleep settings are put back.
if [[ -x /usr/local/bin/keepgoing-helper ]]; then
  /usr/local/bin/keepgoing-helper disable >/dev/null 2>&1 || true
fi

/bin/rm -f /etc/sudoers.d/clamshell-wifi
/bin/rm -f /etc/sudoers.d/keepgoing
/bin/rm -f /usr/local/bin/clamshell-wifi-helper
/bin/rm -f /usr/local/bin/keepgoing-helper
/bin/rm -rf /var/db/keepgoing

echo "uninstalled"
