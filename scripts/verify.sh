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
verify_timeout=${VERIFY_TIMEOUT_SECONDS:-90}
retry_interval=${VERIFY_RETRY_INTERVAL_SECONDS:-2}
case $verify_timeout in *[!0-9]*|'') die 'VERIFY_TIMEOUT_SECONDS must be a non-negative integer' ;; esac
case $retry_interval in *[!0-9]*|'') die 'VERIFY_RETRY_INTERVAL_SECONDS must be a non-negative integer' ;; esac
started_at=$(date +%s)
http_ready=false
info "Waiting up to $verify_timeout seconds for Alloy's local HTTP endpoints"
while systemctl is-active --quiet alloy; do
    ready_ok=false
    healthy_ok=false
    curl -fsS --connect-timeout 3 "http://$address/-/ready" >/dev/null 2>&1 && ready_ok=true
    curl -fsS --connect-timeout 3 "http://$address/-/healthy" >/dev/null 2>&1 && healthy_ok=true
    if [ "$ready_ok" = true ] && [ "$healthy_ok" = true ]; then
        http_ready=true
        break
    fi
    now=$(date +%s)
    [ $((now - started_at)) -lt "$verify_timeout" ] || break
    sleep "$retry_interval"
done
if [ "$http_ready" = true ]; then
    ok 'Alloy ready endpoint passed'
    ok 'Alloy healthy endpoint passed'
else
    error "Alloy did not become ready and healthy within $verify_timeout seconds"
    failed=1
fi

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
auth_enabled=$(config_get "$parsed" OBSERVABILITY_AUTH_ENABLED)
if ! check_endpoint_code Prometheus "$(curl_endpoint_status "$(config_get "$parsed" PROMETHEUS_WRITE_URL)" "$username" "$password" "$auth_enabled")"; then
    if [ "${VERIFY_EXTERNAL_STRICT:-1}" = 1 ]; then failed=1; else warn 'Prometheus connectivity is external and did not invalidate the local deployment.'; fi
fi
if ! check_endpoint_code Loki "$(curl_endpoint_status "$(config_get "$parsed" LOKI_WRITE_URL)" "$username" "$password" "$auth_enabled")"; then
    if [ "${VERIFY_EXTERNAL_STRICT:-1}" = 1 ]; then failed=1; else warn 'Loki connectivity is external and did not invalidate the local deployment.'; fi
fi

if journalctl -u alloy --since '-2 minutes' --no-pager 2>/dev/null | grep -Ei 'fatal|panic' >/dev/null; then
    error 'Recent Alloy journal entries contain a fatal error or panic.'
    failed=1
elif journalctl -u alloy --since '-2 minutes' --no-pager 2>/dev/null | grep -Ei 'level=error' >/dev/null; then
    warn 'Recent Alloy journal entries contain errors; inspect journalctl -u alloy.'
fi
exit "$failed"
