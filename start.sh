#!/bin/sh
set -eu
PROJECT_ROOT=${PROJECT_ROOT:-$(CDPATH='' cd -- "$(dirname "$0")" && pwd)}
. "$PROJECT_ROOT/scripts/common.sh"
require_root

info 'Starting idempotent per-host observability deployment'
sh "$PROJECT_ROOT/check-configs.sh"
sh "$PROJECT_ROOT/scripts/install-alloy.sh"
sh "$PROJECT_ROOT/scripts/configure-permissions.sh"

staging=$(mktemp -d /etc/alloy/.per-host-observe.render.XXXXXX)
trap 'if [ -d "$staging" ]; then find "$staging" -type f -delete 2>/dev/null; rmdir "$staging" 2>/dev/null || true; fi' EXIT HUP INT TERM
sh "$PROJECT_ROOT/scripts/render-config.sh" "$staging/config"

export_runtime_environment "$PROJECT_ROOT"
for file in "$staging/config/"*.alloy; do alloy fmt --write "$file" >/dev/null; done
alloy validate "$staging/config"
ok 'Rendered Alloy configuration is formatted and valid'

marker_before=$(sed -n '1p' /var/lib/per-host-observe/last-backup 2>/dev/null || true)
if ! sh "$PROJECT_ROOT/scripts/deploy-config.sh" "$staging/config"; then
    error 'Atomic deployment failed; attempting to restore the previous snapshot.'
    marker_after=$(sed -n '1p' /var/lib/per-host-observe/last-backup 2>/dev/null || true)
    if [ -n "$marker_after" ] && [ "$marker_after" != "$marker_before" ]; then sh "$PROJECT_ROOT/scripts/rollback.sh" || true; fi
    die 'Configuration deployment failed.'
fi
systemctl daemon-reload
systemctl enable alloy >/dev/null
if systemctl restart alloy && VERIFY_EXTERNAL_STRICT=0 sh "$PROJECT_ROOT/scripts/verify.sh"; then
    backup_count=0
    for old_backup in $(find /var/lib/per-host-observe/backups -mindepth 1 -maxdepth 1 -type d -name '20*' -print | LC_ALL=C sort -r); do
        backup_count=$((backup_count + 1))
        if [ "$backup_count" -gt 5 ]; then
            find "$old_backup" -depth -type f -delete
            find "$old_backup" -depth -type d -empty -delete
        fi
    done
    ok 'Per-host observability is active and healthy'
    sh "$PROJECT_ROOT/status.sh"
else
    error 'New configuration failed health checks; rolling back automatically.'
    sh "$PROJECT_ROOT/scripts/rollback.sh"
    systemctl restart alloy || true
    die 'Deployment failed and the previous configuration was restored. Inspect: journalctl -u alloy'
fi
