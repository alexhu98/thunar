#!/bin/bash
# One-time setup of the Thunar updater on a machine: sudo deploy/setup.sh
# Installs the updater, its timer, the apt pin and the GitHub token, then enables the timer.
set -euo pipefail

[[ $EUID == 0 ]] || { echo "Run it as root: sudo $0" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)

apt-get install -y curl python3 libnotify-bin

install -m 755 "$here/thunar-update" /usr/local/sbin/thunar-update
install -m 644 "$here/thunar-update.service" "$here/thunar-update.timer" /etc/systemd/system/
install -m 644 "$here/thunar-custom" /etc/apt/preferences.d/thunar-custom
install -d -m 700 /etc/thunar-update

if [[ -s /etc/thunar-update/token ]] && [[ ${1:-} != --new-token ]]; then
  echo "Keeping the token in /etc/thunar-update/token (pass --new-token to replace it)."
else
  read -rsp "GitHub token (Contents: read on alexhu98/thunar): " token
  echo
  [[ -n $token ]] || { echo "No token given." >&2; exit 1; }
  (umask 077 && printf '%s\n' "$token" >/etc/thunar-update/token)
fi
chmod 600 /etc/thunar-update/token

systemctl daemon-reload
systemctl enable --now thunar-update.timer
systemctl list-timers thunar-update.timer --no-pager
echo "Installed. To update now: sudo systemctl start thunar-update; journalctl -u thunar-update"
