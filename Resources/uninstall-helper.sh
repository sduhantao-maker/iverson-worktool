#!/bin/zsh
set -eu

/bin/rm -f /etc/sudoers.d/clamshell-wifi
/bin/rm -f /etc/sudoers.d/keepgoing
/bin/rm -f /usr/local/bin/clamshell-wifi-helper
/bin/rm -f /usr/local/bin/keepgoing-helper

echo "uninstalled"
