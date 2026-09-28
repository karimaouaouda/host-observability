#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"
require_root
if [ "${1:-}" != --yes ]; then
    printf 'Remove per-host-observe configuration and permissions, preserving Alloy package/data? [y/N] '
    read -r answer
    case $answer in y|Y|yes|YES) ;; *) info 'Uninstall cancelled'; exit 0 ;; esac
fi
systemctl stop alloy 2>/dev/null || true
alloy_binary=$(command -v alloy 2>/dev/null || true)
[ -z "$alloy_binary" ] || setcap -r "$alloy_binary" 2>/dev/null || true
if [ -f /var/lib/per-host-observe/added-docker-group ] && getent passwd alloy >/dev/null && getent group docker >/dev/null; then
    gpasswd -d alloy docker >/dev/null 2>&1 || true
fi
if [ -f /var/lib/per-host-observe/nginx-acl-paths ] && getent passwd alloy >/dev/null; then
    sort -u /var/lib/per-host-observe/nginx-acl-paths | while IFS= read -r log_path; do
        [ -n "$log_path" ] || continue
        log_dir=$(dirname "$log_path")
        setfacl -x u:alloy "$log_path" 2>/dev/null || true
        setfacl -x u:alloy "$log_dir" 2>/dev/null || true
        setfacl -x d:u:alloy "$log_dir" 2>/dev/null || true
    done
fi
for target in /etc/alloy/per-host-observe /etc/per-host-observe /etc/systemd/system/alloy.service.d/per-host-observe.conf; do
    if [ -d "$target" ]; then find "$target" -depth -type f -delete; find "$target" -depth -type d -empty -delete; elif [ -f "$target" ]; then unlink "$target"; fi
done
if [ -f /var/lib/per-host-observe/original-alloy.defaults ]; then
    install -o root -g root -m 0644 /var/lib/per-host-observe/original-alloy.defaults /etc/default/alloy
fi
systemctl daemon-reload
warn 'Removed project-owned configuration and permissions. Backups and /var/lib/alloy were preserved for recovery.'
