#!/bin/sh
set -u

PROJECT_ROOT=${PROJECT_ROOT:-$(CDPATH='' cd -- "$(dirname "$0")" && pwd)}
. "$PROJECT_ROOT/scripts/common.sh"
failed=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

info 'Validating per-host observability configuration'
if [ "${SKIP_PLATFORM_CHECKS:-0}" != 1 ]; then
    [ "$(uname -s)" = Linux ] || { error 'Only Linux is supported'; failed=1; }
    [ -r /etc/os-release ] || { error '/etc/os-release is unavailable'; failed=1; }
    if [ -r /etc/os-release ]; then
        os_id=$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')
        case $os_id in ubuntu|debian) ok "Supported operating system: $os_id" ;; *) error "Unsupported distribution: $os_id"; failed=1 ;; esac
    fi
    case $(uname -m) in x86_64|aarch64|arm64) ok "Supported architecture: $(uname -m)" ;; *) error "Unsupported architecture: $(uname -m)"; failed=1 ;; esac
    [ -d /run/systemd/system ] || { error 'systemd is required'; failed=1; }
    [ "$(id -u)" -eq 0 ] || { error 'Run check-configs.sh with sudo/root'; failed=1; }
    for tool in curl git systemctl docker getent sed awk grep find mktemp; do
        command_exists "$tool" || { error "Required command is missing: $tool"; failed=1; }
    done
fi

if ! config_parse "$PROJECT_ROOT/.env" "$GLOBAL_KEYS" "$tmp/global"; then
    failed=1
elif validate_global_config "$tmp/global"; then
    ok 'Global configuration is valid'
else
    failed=1
fi

if [ -f "$tmp/global" ]; then
    docker_metrics=$(config_get "$tmp/global" ENABLE_DOCKER_METRICS)
    docker_logs=$(config_get "$tmp/global" ENABLE_DOCKER_LOGS)
    if [ "${SKIP_RUNTIME_CHECKS:-0}" != 1 ] && { is_true "$docker_metrics" || is_true "$docker_logs"; }; then
        [ -S /var/run/docker.sock ] || { error 'Docker socket /var/run/docker.sock is unavailable'; failed=1; }
        docker info >/dev/null 2>&1 || { error 'Docker daemon is unavailable'; failed=1; }
    fi
    if is_true "$(config_get "$tmp/global" ENABLE_NGINX_LOGS)"; then
        for key in NGINX_ACCESS_LOG NGINX_ERROR_LOG; do
            path=$(config_get "$tmp/global" "$key")
            if [ -e "$path" ]; then ok "NGINX log exists: $path"; else warn "NGINX log does not yet exist: $path"; fi
        done
    fi
    if is_true "$(config_get "$tmp/global" ENABLE_BEYLA)"; then
        kernel=$(uname -r)
        kernel_major=${kernel%%.*}; kernel_rest=${kernel#*.}; kernel_minor=${kernel_rest%%.*}
        if [ "$kernel_major" -lt 4 ] || { [ "$kernel_major" -eq 4 ] && [ "$kernel_minor" -lt 18 ]; }; then
            error "Beyla requires a modern eBPF-capable kernel; found $kernel"
            failed=1
        else
            ok "Kernel $kernel is new enough for Beyla's baseline eBPF support"
        fi
        [ -r /sys/kernel/btf/vmlinux ] || warn 'Kernel BTF is unavailable; Beyla support depends on compatible kernel headers.'
    fi
fi

for spec in "postgres:$POSTGRES_KEYS:NAME DSN AUTODISCOVERY APP SERVICE" "mysql:$MYSQL_KEYS:NAME DSN APP SERVICE" "redis:$REDIS_KEYS:NAME ADDRESS APP SERVICE"; do
    type=${spec%%:*}; rest=${spec#*:}; keys=${rest%%:*}; required=${rest#*:}; seen=' '
    for file in "$PROJECT_ROOT/instances/$type/"*.env; do
        [ -f "$file" ] || continue
        if ! config_parse "$file" "$keys" "$tmp/instance"; then failed=1; continue; fi
        for key in $required; do require_config "$tmp/instance" "$key" || failed=1; done
        name=$(config_get "$tmp/instance" NAME); id=$(alloy_identifier "$name")
        [ -n "$id" ] || { error "$type NAME does not produce a valid Alloy identifier"; failed=1; continue; }
        case "$seen" in *" $id "*) error "Duplicate $type NAME after sanitizing: $name"; failed=1 ;; *) seen="$seen$id " ;; esac
        if [ "$type" = postgres ]; then validate_bool AUTODISCOVERY "$(config_get "$tmp/instance" AUTODISCOVERY)" || failed=1; fi
    done
done

if [ "$failed" -eq 0 ] && [ -f "$tmp/global" ]; then
    if "$PROJECT_ROOT/scripts/render-config.sh" "$tmp/rendered" >/dev/null; then ok 'Configuration renders successfully'; else failed=1; fi
fi
if [ "$failed" -eq 0 ] && command_exists alloy; then
    export_runtime_environment "$PROJECT_ROOT"
    if alloy validate "$tmp/rendered" >/dev/null; then
        ok 'Alloy syntax validation passed'
    else
        error 'Alloy syntax validation failed'
        failed=1
    fi
else
    command_exists alloy || info 'Alloy is not installed; syntax validation will run during start.sh'
fi
if [ "$failed" -eq 0 ] && [ "${SKIP_CONNECTIVITY_CHECKS:-0}" != 1 ]; then
    username=$(config_get "$tmp/global" OBSERVABILITY_USERNAME)
    password=$(config_get "$tmp/global" OBSERVABILITY_PASSWORD)
    check_endpoint_code Prometheus "$(curl_endpoint_status "$(config_get "$tmp/global" PROMETHEUS_WRITE_URL)" "$username" "$password")" || failed=1
    check_endpoint_code Loki "$(curl_endpoint_status "$(config_get "$tmp/global" LOKI_WRITE_URL)" "$username" "$password")" || failed=1
    if curl -fsS -o /dev/null --connect-timeout 8 --max-time 15 "$(config_get "$tmp/global" GRAFANA_URL)"; then
        ok 'Grafana DNS/TLS/connectivity check passed'
    else
        error 'Grafana failed DNS, TLS, or HTTP connectivity checks'
        failed=1
    fi
fi

if [ "$failed" -eq 0 ]; then ok 'All configuration checks passed'; else error 'Configuration checks failed'; fi
exit "$failed"
