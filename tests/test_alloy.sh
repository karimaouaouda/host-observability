#!/bin/sh
set -eu

. "$(dirname "$0")/test_helper.sh"
alloy_bin=${ALLOY_BIN:-}
if [ -z "$alloy_bin" ]; then alloy_bin=$(command -v alloy 2>/dev/null || true); fi
if [ -z "$alloy_bin" ]; then
    printf 'ok - Alloy binary unavailable (integration validation skipped)\n'
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cp -R "$TEST_ROOT/." "$tmp/project"
cd "$tmp/project"
cp .env.example .env
sed -i 's/CHANGE_ME/integration-secret/' .env
cp examples/postgres.example.env instances/postgres/app.env
cp examples/mysql.example.env instances/mysql/shop.env
cp examples/redis.example.env instances/redis/cache.env
PROJECT_ROOT=$PWD sh scripts/render-config.sh "$tmp/rendered" >/dev/null
. scripts/common.sh
export_runtime_environment "$PWD"
for config in "$tmp/rendered/"*.alloy; do "$alloy_bin" fmt --write "$config" >/dev/null; done
if "$alloy_bin" validate "$tmp/rendered"; then
    pass 'Alloy accepts the complete generated configuration'
else
    fail 'Alloy accepts the complete generated configuration'
fi

cp examples/central-vps.example.env .env
sed -i 's/TLS_INSECURE_SKIP_VERIFY=false/TLS_INSECURE_SKIP_VERIFY=true/' .env
PROJECT_ROOT=$PWD sh scripts/render-config.sh "$tmp/loopback-rendered" >/dev/null
export_runtime_environment "$PWD"
for config in "$tmp/loopback-rendered/"*.alloy; do "$alloy_bin" fmt --write "$config" >/dev/null; done
if "$alloy_bin" validate "$tmp/loopback-rendered"; then
    pass 'Alloy accepts auth-free central VPS loopback configuration'
else
    fail 'Alloy accepts auth-free central VPS loopback configuration'
fi
finish
