#!/bin/sh

# Shared POSIX helpers. Configuration files are parsed as data and never sourced.
PROJECT_ROOT=${PROJECT_ROOT:-$(CDPATH='' cd -- "$(dirname "$0")/.." 2>/dev/null && pwd)}
GLOBAL_KEYS='HOST_ID ENVIRONMENT REGION DATACENTER GRAFANA_URL PROMETHEUS_WRITE_URL LOKI_WRITE_URL OBSERVABILITY_AUTH_ENABLED OBSERVABILITY_USERNAME OBSERVABILITY_PASSWORD TLS_INSECURE_SKIP_VERIFY ENABLE_HOST_METRICS ENABLE_DOCKER_METRICS ENABLE_DOCKER_LOGS DOCKER_HOST ENABLE_NGINX_LOGS NGINX_ACCESS_LOG NGINX_ERROR_LOG ENABLE_BEYLA BEYLA_CONTAINERS_ONLY BEYLA_OPEN_PORTS ALLOY_HTTP_ADDRESS'
POSTGRES_KEYS='NAME DSN AUTODISCOVERY APP SERVICE'
MYSQL_KEYS='NAME DSN APP SERVICE'
REDIS_KEYS='NAME ADDRESS USERNAME PASSWORD APP SERVICE'

log() ( level=$1; shift; printf '[%s] %s\n' "$level" "$*"; )
ok() { log OK "$@"; }
info() { log INFO "$@"; }
warn() { log WARN "$@" >&2; }
error() { log ERROR "$@" >&2; }
die() { error "$@"; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }
is_true() { [ "${1:-}" = true ]; }
is_loopback_url() {
    case $1 in
        http://127.0.0.1|http://127.0.0.1/*|http://127.0.0.1:*|http://localhost|http://localhost/*|http://localhost:*|https://127.0.0.1|https://127.0.0.1/*|https://127.0.0.1:*|https://localhost|https://localhost/*|https://localhost:*) return 0 ;;
        *) return 1 ;;
    esac
}

config_parse() (
    input=$1 allowed=$2 output=$3
    [ -f "$input" ] || { error "Configuration file not found: $input"; return 1; }
    : >"$output" || return 1
    seen=' '; line_no=0
    while IFS= read -r line || [ -n "$line" ]; do
        line_no=$((line_no + 1))
        case $line in ''|'#'*) continue ;; esac
        case $line in *=*) ;; *) error "$input:$line_no: expected KEY=value"; return 1 ;; esac
        key=${line%%=*}; value=${line#*=}
        case $key in *[!A-Z0-9_]*|'') error "$input:$line_no: invalid key name"; return 1 ;; esac
        case " $allowed " in *" $key "*) ;; *) error "$input:$line_no: unknown key '$key'"; return 1 ;; esac
        case "$seen" in *" $key "*) error "$input:$line_no: duplicate key '$key'"; return 1 ;; esac
        seen="$seen$key "
        printf '%s=%s\n' "$key" "$value" >>"$output"
    done <"$input"
)

config_get() (
    parsed=$1 key=$2
    awk -v wanted="$key" 'index($0, wanted "=") == 1 { print substr($0, length(wanted) + 2); exit }' "$parsed"
)
require_config() (
    required_parsed=$1 required_key=$2 required_value=$(config_get "$required_parsed" "$required_key")
    [ -n "$required_value" ] || { error "Required setting $required_key is empty"; return 1; }
)
validate_bool() { case $2 in true|false) return 0 ;; *) error "$1 must be true or false"; return 1 ;; esac; }
alloy_identifier() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g; s/^\([0-9]\)/_\1/'; }
env_identifier() { printf '%s' "$1" | tr '[:lower:]-.' '[:upper:]__' | sed 's/[^A-Z0-9_]/_/g'; }
alloy_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

env_write() (
    key=$1 value=$2 output=$3
    escaped=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '%s="%s"\n' "$key" "$escaped" >>"$output"
)

validate_open_ports() (
    ports=$1
    [ -n "$ports" ] || return 1
    [ "$ports" != '1-65535' ] || return 1
    old_ifs=$IFS; IFS=,
    # shellcheck disable=SC2086 # Intentional split of a validated comma list.
    set -- $ports
    IFS=$old_ifs
    for item do
        case $item in
            *-*) start=${item%-*}; end=${item#*-}; case "$start$end" in *[!0-9]*) return 1 ;; esac; [ "$start" -ge 1 ] 2>/dev/null && [ "$end" -le 65535 ] && [ "$start" -le "$end" ] || return 1 ;;
            *) case $item in *[!0-9]*|'') return 1 ;; esac; [ "$item" -ge 1 ] 2>/dev/null && [ "$item" -le 65535 ] || return 1 ;;
        esac
    done
)

validate_global_config() (
    parsed=$1 failed=0
    for key in HOST_ID ENVIRONMENT GRAFANA_URL PROMETHEUS_WRITE_URL LOKI_WRITE_URL; do
        require_config "$parsed" "$key" || failed=1
    done
    host_id=$(config_get "$parsed" HOST_ID)
    case $host_id in *[!a-zA-Z0-9_.-]*|'') error 'HOST_ID may contain only letters, numbers, dot, underscore, and hyphen'; failed=1 ;; esac
    environment=$(config_get "$parsed" ENVIRONMENT)
    case $environment in *[!a-zA-Z0-9_.-]*|'') error 'ENVIRONMENT may contain only letters, numbers, dot, underscore, and hyphen'; failed=1 ;; esac
    auth_enabled=$(config_get "$parsed" OBSERVABILITY_AUTH_ENABLED)
    validate_bool OBSERVABILITY_AUTH_ENABLED "$auth_enabled" || failed=1
    if is_true "$auth_enabled"; then
        require_config "$parsed" OBSERVABILITY_USERNAME || failed=1
        require_config "$parsed" OBSERVABILITY_PASSWORD || failed=1
        [ "$(config_get "$parsed" OBSERVABILITY_PASSWORD)" != CHANGE_ME ] || { error 'OBSERVABILITY_PASSWORD still uses CHANGE_ME'; failed=1; }
    else
        for key in PROMETHEUS_WRITE_URL LOKI_WRITE_URL; do
            is_loopback_url "$(config_get "$parsed" "$key")" || { error "OBSERVABILITY_AUTH_ENABLED=false is allowed only for loopback ingestion URLs"; failed=1; }
        done
    fi
    for key in GRAFANA_URL PROMETHEUS_WRITE_URL LOKI_WRITE_URL; do
        value=$(config_get "$parsed" "$key")
        case $value in
            https://*) ;;
            *) is_loopback_url "$value" || { error "$key must use HTTPS unless it targets 127.0.0.1 or localhost"; failed=1; } ;;
        esac
    done
    for key in TLS_INSECURE_SKIP_VERIFY ENABLE_HOST_METRICS ENABLE_DOCKER_METRICS ENABLE_DOCKER_LOGS ENABLE_NGINX_LOGS ENABLE_BEYLA BEYLA_CONTAINERS_ONLY; do
        validate_bool "$key" "$(config_get "$parsed" "$key")" || failed=1
    done
    if is_true "$(config_get "$parsed" TLS_INSECURE_SKIP_VERIFY)"; then
        for key in GRAFANA_URL PROMETHEUS_WRITE_URL LOKI_WRITE_URL; do
            is_loopback_url "$(config_get "$parsed" "$key")" || { error 'TLS_INSECURE_SKIP_VERIFY=true is allowed only when all central URLs are loopback'; failed=1; }
        done
    fi
    if is_true "$(config_get "$parsed" ENABLE_BEYLA)"; then
        validate_open_ports "$(config_get "$parsed" BEYLA_OPEN_PORTS)" || { error 'BEYLA_OPEN_PORTS is invalid or dangerously broad'; failed=1; }
    fi
    http_address=$(config_get "$parsed" ALLOY_HTTP_ADDRESS)
    case $http_address in
        127.0.0.1:*)
            http_port=${http_address#*:}
            case $http_port in *[!0-9]*|'') error 'ALLOY_HTTP_ADDRESS must contain a numeric port'; failed=1 ;; *)
                [ "$http_port" -ge 1 ] 2>/dev/null && [ "$http_port" -le 65535 ] || { error 'ALLOY_HTTP_ADDRESS port must be between 1 and 65535'; failed=1; }
            esac
            ;;
        *) error 'ALLOY_HTTP_ADDRESS must use 127.0.0.1 and may not bind publicly'; failed=1 ;;
    esac
    if is_true "$(config_get "$parsed" ENABLE_NGINX_LOGS)"; then
        for path_key in NGINX_ACCESS_LOG NGINX_ERROR_LOG; do
            case $(config_get "$parsed" "$path_key") in /*) ;; *) error "$path_key must be an absolute path"; failed=1 ;; esac
        done
    fi
    return "$failed"
)

# Export validated values without eval, sourcing files, or exposing secrets in argv.
export_runtime_environment() {
    export_root=$1
    export_tmp=$(mktemp -d)
    config_parse "$export_root/.env" "$GLOBAL_KEYS" "$export_tmp/global" || { find "$export_tmp" -type f -delete; rmdir "$export_tmp"; return 1; }
    for export_key in PROMETHEUS_WRITE_URL LOKI_WRITE_URL OBSERVABILITY_USERNAME OBSERVABILITY_PASSWORD DOCKER_HOST; do
        export_value=$(config_get "$export_tmp/global" "$export_key")
        export "$export_key=$export_value"
    done
    for export_file in "$export_root/instances/postgres/"*.env; do
        [ -f "$export_file" ] || continue
        config_parse "$export_file" "$POSTGRES_KEYS" "$export_tmp/instance" || return 1
        export_id=$(env_identifier "$(alloy_identifier "$(config_get "$export_tmp/instance" NAME)")")
        export_value=$(config_get "$export_tmp/instance" DSN)
        export "POSTGRES_${export_id}_DSN=$export_value"
    done
    for export_file in "$export_root/instances/mysql/"*.env; do
        [ -f "$export_file" ] || continue
        config_parse "$export_file" "$MYSQL_KEYS" "$export_tmp/instance" || return 1
        export_id=$(env_identifier "$(alloy_identifier "$(config_get "$export_tmp/instance" NAME)")")
        export_value=$(config_get "$export_tmp/instance" DSN)
        export "MYSQL_${export_id}_DSN=$export_value"
    done
    for export_file in "$export_root/instances/redis/"*.env; do
        [ -f "$export_file" ] || continue
        config_parse "$export_file" "$REDIS_KEYS" "$export_tmp/instance" || return 1
        export_id=$(env_identifier "$(alloy_identifier "$(config_get "$export_tmp/instance" NAME)")")
        export_value=$(config_get "$export_tmp/instance" ADDRESS); export "REDIS_${export_id}_ADDRESS=$export_value"
        export_value=$(config_get "$export_tmp/instance" USERNAME); export "REDIS_${export_id}_USERNAME=$export_value"
        export_value=$(config_get "$export_tmp/instance" PASSWORD); export "REDIS_${export_id}_PASSWORD=$export_value"
    done
    find "$export_tmp" -type f -delete
    rmdir "$export_tmp"
}

instance_files() { dir=$1; [ -d "$dir" ] || return 0; find "$dir" -maxdepth 1 -type f -name '*.env' -print | LC_ALL=C sort; }
count_instances() { instance_files "$1" | awk 'END { print NR + 0 }'; }
require_root() { [ "$(id -u)" -eq 0 ] || die 'Run this command with sudo/root.'; }
version_lt_5_11() (
    version=${1:-$(uname -r)}; major=${version%%.*}; rest=${version#*.}; minor=${rest%%.*}
    [ "$major" -lt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -lt 11 ]; }
)
curl_endpoint_status() (
    url=$1 username=$2 password=$3 auth_enabled=$4
    auth_file=$(mktemp)
    trap 'rm -f "$auth_file"' EXIT HUP INT TERM
    chmod 600 "$auth_file"
    if is_true "$auth_enabled"; then
        escaped_user=$(printf '%s' "$username" | sed 's/\\/\\\\/g; s/"/\\"/g')
        escaped_password=$(printf '%s' "$password" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf 'user = "%s:%s"\n' "$escaped_user" "$escaped_password" >"$auth_file"
    else
        : >"$auth_file"
    fi
    status=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 8 --max-time 15 --config "$auth_file" -X POST "$url" 2>/dev/null) || status=000
    printf '%s' "$status"
)
check_endpoint_code() (
    name=$1 code=$2
    case $code in
        200|204|400|405) ok "$name endpoint is reachable (HTTP $code)" ;;
        401|403) error "$name authentication was rejected (HTTP $code)"; return 1 ;;
        404) error "$name endpoint path was not found (HTTP 404)"; return 1 ;;
        000) error "$name endpoint failed DNS, TLS, or network connectivity"; return 1 ;;
        *) warn "$name endpoint returned HTTP $code; verify the upstream ingress" ;;
    esac
)
