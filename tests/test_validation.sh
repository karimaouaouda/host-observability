#!/bin/sh

. "$(dirname "$0")/test_helper.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cp -R "$TEST_ROOT/." "$tmp/project"
cd "$tmp/project" || exit 1

if PROJECT_ROOT=$PWD SKIP_PLATFORM_CHECKS=1 SKIP_CONNECTIVITY_CHECKS=1 sh check-configs.sh >"$tmp/missing" 2>&1; then
    fail 'missing .env fails validation'
else
    pass 'missing .env fails validation'
fi

cp .env.example .env
if PROJECT_ROOT=$PWD SKIP_PLATFORM_CHECKS=1 SKIP_CONNECTIVITY_CHECKS=1 sh check-configs.sh >"$tmp/placeholder" 2>&1; then
    fail 'placeholder password fails validation'
else
    pass 'placeholder password fails validation'
fi

sed -i 's/OBSERVABILITY_PASSWORD=CHANGE_ME/OBSERVABILITY_PASSWORD=test-secret/' .env
if PROJECT_ROOT=$PWD SKIP_PLATFORM_CHECKS=1 SKIP_CONNECTIVITY_CHECKS=1 SKIP_RUNTIME_CHECKS=1 sh check-configs.sh >"$tmp/good" 2>&1; then
    pass 'valid configuration passes offline validation'
else
    fail 'valid configuration passes offline validation'
    sed -n '1,160p' "$tmp/good" >&2
fi
assert_not_contains 'validation never prints password' "$tmp/good" 'test-secret'

cp .env.example .env
sed -i 's#GRAFANA_URL=https://grafana.karimaouaouda.space#GRAFANA_URL=http://127.0.0.1:3000#' .env
sed -i 's#PROMETHEUS_WRITE_URL=https://observability.karimaouaouda.space/prometheus/write#PROMETHEUS_WRITE_URL=http://127.0.0.1:9090/api/v1/write#' .env
sed -i 's#LOKI_WRITE_URL=https://observability.karimaouaouda.space/loki/push#LOKI_WRITE_URL=http://127.0.0.1:3100/loki/api/v1/push#' .env
sed -i 's/OBSERVABILITY_AUTH_ENABLED=true/OBSERVABILITY_AUTH_ENABLED=false/' .env
sed -i 's/OBSERVABILITY_USERNAME=my-vps-01/OBSERVABILITY_USERNAME=/' .env
sed -i 's/OBSERVABILITY_PASSWORD=CHANGE_ME/OBSERVABILITY_PASSWORD=/' .env
if PROJECT_ROOT=$PWD SKIP_PLATFORM_CHECKS=1 SKIP_CONNECTIVITY_CHECKS=1 SKIP_RUNTIME_CHECKS=1 sh check-configs.sh >"$tmp/loopback" 2>&1; then
    pass 'loopback HTTP endpoints without Basic Auth are valid'
else
    fail 'loopback HTTP endpoints without Basic Auth are valid'
    sed -n '1,160p' "$tmp/loopback" >&2
fi

sed -i 's/TLS_INSECURE_SKIP_VERIFY=false/TLS_INSECURE_SKIP_VERIFY=true/' .env
if PROJECT_ROOT=$PWD SKIP_PLATFORM_CHECKS=1 SKIP_CONNECTIVITY_CHECKS=1 SKIP_RUNTIME_CHECKS=1 sh check-configs.sh >"$tmp/loopback-insecure-tls" 2>&1; then
    pass 'loopback endpoints may explicitly disable TLS verification'
else
    fail 'loopback endpoints may explicitly disable TLS verification'
fi

sed -i 's#GRAFANA_URL=http://127.0.0.1:3000#GRAFANA_URL=http://grafana.example.com#' .env
if PROJECT_ROOT=$PWD SKIP_PLATFORM_CHECKS=1 SKIP_CONNECTIVITY_CHECKS=1 SKIP_RUNTIME_CHECKS=1 sh check-configs.sh >"$tmp/remote-http" 2>&1; then
    fail 'remote plain HTTP endpoint is rejected'
else
    pass 'remote plain HTTP endpoint is rejected'
fi

sed -i 's#GRAFANA_URL=http://grafana.example.com#GRAFANA_URL=https://grafana.example.com#' .env
if PROJECT_ROOT=$PWD SKIP_PLATFORM_CHECKS=1 SKIP_CONNECTIVITY_CHECKS=1 SKIP_RUNTIME_CHECKS=1 sh check-configs.sh >"$tmp/remote-insecure-tls" 2>&1; then
    fail 'remote endpoint cannot disable TLS verification'
else
    pass 'remote endpoint cannot disable TLS verification'
fi

finish
