#!/bin/sh
set -u
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
PROJECT_ROOT=${PROJECT_ROOT:-$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)}
. "$SCRIPT_DIR/common.sh"
failed=0
parsed=$(mktemp)
trap 'rm -f "$parsed"' EXIT HUP INT TERM
config_parse "$PROJECT_ROOT/.env" "$GLOBAL_KEYS" "$parsed" || exit 1

if systemctl is-active --quiet alloy; then ok 'Alloy service is active'; else error 'Alloy service is not active'; failed=1; fi
address=$(config_get "$parsed" ALLOY_HTTP_ADDRESS)
for endpoint in ready healthy; do
    if curl -fsS --connect-timeout 3 "http://$address/-/$endpoint" >/dev/null; then
        ok "Alloy $endpoint endpoint passed"
    else
        error "Alloy $endpoint endpoint failed"
        failed=1
    fi
done

if is_true "$(config_get "$parsed" ENABLE_DOCKER_METRICS)" || is_true "$(config_get "$parsed" ENABLE_DOCKER_LOGS)"; then
    if runuser -u alloy -- docker info >/dev/null 2>&1; then ok 'Alloy can access Docker'; else error 'The alloy user cannot access Docker'; failed=1; fi
fi
if is_true "$(config_get "$parsed" ENABLE_NGINX_LOGS)"; then
    for key in NGINX_ACCESS_LOG NGINX_ERROR_LOG; do
        path=$(config_get "$parsed" "$key")
        [ ! -e "$path" ] || runuser -u alloy -- test -r "$path" || { error "Alloy cannot read NGINX log: $path"; failed=1; }
    done
fi

username=$(config_get "$parsed" OBSERVABILITY_USERNAME)
password=$(config_get "$parsed" OBSERVABILITY_PASSWORD)
if ! check_endpoint_code Prometheus "$(curl_endpoint_status "$(config_get "$parsed" PROMETHEUS_WRITE_URL)" "$username" "$password")"; then
    if [ "${VERIFY_EXTERNAL_STRICT:-1}" = 1 ]; then failed=1; else warn 'Prometheus connectivity is external and did not invalidate the local deployment.'; fi
fi
if ! check_endpoint_code Loki "$(curl_endpoint_status "$(config_get "$parsed" LOKI_WRITE_URL)" "$username" "$password")"; then
    if [ "${VERIFY_EXTERNAL_STRICT:-1}" = 1 ]; then failed=1; else warn 'Loki connectivity is external and did not invalidate the local deployment.'; fi
fi

if journalctl -u alloy --since '-2 minutes' --no-pager 2>/dev/null | grep -Ei 'fatal|panic' >/dev/null; then
    error 'Recent Alloy journal entries contain a fatal error or panic.'
    failed=1
elif journalctl -u alloy --since '-2 minutes' --no-pager 2>/dev/null | grep -Ei 'level=error' >/dev/null; then
    warn 'Recent Alloy journal entries contain errors; inspect journalctl -u alloy.'
fi
exit "$failed"
