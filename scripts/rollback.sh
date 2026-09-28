#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"
require_root

marker=/var/lib/per-host-observe/last-backup
[ -f "$marker" ] || die 'No rollback snapshot is recorded.'
backup=$(sed -n '1p' "$marker")
case $backup in /var/lib/per-host-observe/backups/*) ;; *) die 'Invalid rollback snapshot path.' ;; esac
[ -d "$backup" ] || die "Rollback snapshot is missing: $backup"
failed=/var/lib/per-host-observe/backups/failed-$(date -u +%Y%m%dT%H%M%SZ)
install -d -m 0750 "$failed"
[ ! -d /etc/alloy/per-host-observe ] || mv /etc/alloy/per-host-observe "$failed/config"
if [ -d "$backup/config" ]; then mv "$backup/config" /etc/alloy/per-host-observe; fi
if [ -f "$backup/agent.env" ]; then install -o root -g alloy -m 0640 "$backup/agent.env" /etc/per-host-observe/agent.env; fi
if [ -f "$backup/alloy.defaults" ]; then install -o root -g root -m 0644 "$backup/alloy.defaults" /etc/default/alloy; fi
warn "Restored previous configuration from $backup; failed candidate retained at $failed"
