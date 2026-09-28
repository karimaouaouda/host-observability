#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"
require_root

staging=${1:-}
[ -d "$staging" ] || die 'Usage: deploy-config.sh STAGING_DIRECTORY'
live=/etc/alloy/per-host-observe
secrets=/etc/per-host-observe/agent.env
backups=/var/lib/per-host-observe/backups
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup=$backups/$timestamp-$$
candidate=/etc/alloy/.per-host-observe.candidate.$$
trap 'if [ -d "$candidate" ]; then find "$candidate" -type f -delete; rmdir "$candidate" 2>/dev/null || true; fi' EXIT HUP INT TERM

install -d -o root -g alloy -m 0750 "$candidate" "$backups" /etc/per-host-observe
for file in "$staging/"*.alloy; do
    install -o root -g alloy -m 0640 "$file" "$candidate/$(basename "$file")"
done
install -o root -g alloy -m 0640 "$staging/agent.env" /etc/per-host-observe/.agent.env.new
install -o root -g root -m 0644 "$staging/alloy.defaults" /etc/default/.alloy.new

install -d -o root -g root -m 0750 "$backup"
if [ -d "$live" ]; then mv "$live" "$backup/config"; fi
if [ -f "$secrets" ]; then cp -p "$secrets" "$backup/agent.env"; fi
if [ -f /etc/default/alloy ]; then cp -p /etc/default/alloy "$backup/alloy.defaults"; fi
if [ ! -f /var/lib/per-host-observe/original-alloy.defaults ] && [ -f /etc/default/alloy ]; then
    cp -p /etc/default/alloy /var/lib/per-host-observe/original-alloy.defaults
fi
printf '%s\n' "$backup" >/var/lib/per-host-observe/last-backup

mv "$candidate" "$live"
mv /etc/per-host-observe/.agent.env.new "$secrets"
mv /etc/default/.alloy.new /etc/default/alloy
ok "Deployed configuration; rollback snapshot: $backup"
