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

finish
