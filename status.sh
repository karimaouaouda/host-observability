#!/bin/sh
set -u
PROJECT_ROOT=${PROJECT_ROOT:-$(CDPATH='' cd -- "$(dirname "$0")" && pwd)}
. "$PROJECT_ROOT/scripts/common.sh"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT HUP INT TERM
if config_parse "$PROJECT_ROOT/.env" "$GLOBAL_KEYS" "$tmp" 2>/dev/null; then
    host_id=$(config_get "$tmp" HOST_ID); environment=$(config_get "$tmp" ENVIRONMENT)
    grafana=$(config_get "$tmp" GRAFANA_URL); address=$(config_get "$tmp" ALLOY_HTTP_ADDRESS)
    central_user=$(config_get "$tmp" OBSERVABILITY_USERNAME)
    central_password=$(config_get "$tmp" OBSERVABILITY_PASSWORD)
    auth_enabled=$(config_get "$tmp" OBSERVABILITY_AUTH_ENABLED)
    prometheus_code=$(curl_endpoint_status "$(config_get "$tmp" PROMETHEUS_WRITE_URL)" "$central_user" "$central_password" "$auth_enabled")
    loki_code=$(curl_endpoint_status "$(config_get "$tmp" LOKI_WRITE_URL)" "$central_user" "$central_password" "$auth_enabled")
else
    host_id='configuration unavailable'; environment='configuration unavailable'
    grafana='configuration unavailable'; address='127.0.0.1:12345'
    prometheus_code=000; loki_code=000
fi
if command_exists alloy; then installed=yes; version=$(alloy --version 2>/dev/null | head -1); else installed=no; version='n/a'; fi
systemctl is-active --quiet alloy 2>/dev/null && service=active || service=inactive
curl -fsS --connect-timeout 2 "http://$address/-/ready" >/dev/null 2>&1 && ready=yes || ready=no
curl -fsS --connect-timeout 2 "http://$address/-/healthy" >/dev/null 2>&1 && healthy=yes || healthy=no
setting() { value=$(config_get "$tmp" "$1" 2>/dev/null); [ "$value" = true ] && printf enabled || printf disabled; }
reachable() { case $1 in 200|204|400|405) printf reachable ;; 401|403) printf 'authentication failed' ;; 404) printf 'wrong path' ;; *) printf unreachable ;; esac; }
cat <<EOF
Per-host Observability
────────────────────────────────────

Host
  ID:             $host_id
  Environment:    $environment

Alloy
  Installed:      $installed
  Version:        $version
  Service:        $service
  Ready:          $ready
  Healthy:        $healthy

Central
  Prometheus:     $(reachable "$prometheus_code")
  Loki:           $(reachable "$loki_code")
  Grafana:        $grafana

Collectors
  Host metrics:   $(setting ENABLE_HOST_METRICS)
  Docker metrics: $(setting ENABLE_DOCKER_METRICS)
  Docker logs:    $(setting ENABLE_DOCKER_LOGS)
  NGINX logs:     $(setting ENABLE_NGINX_LOGS)
  Beyla:          $(setting ENABLE_BEYLA)

Databases
  PostgreSQL:     $(count_instances "$PROJECT_ROOT/instances/postgres")
  MySQL:          $(count_instances "$PROJECT_ROOT/instances/mysql")
  Redis:          $(count_instances "$PROJECT_ROOT/instances/redis")
EOF
