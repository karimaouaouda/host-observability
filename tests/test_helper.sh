#!/bin/sh

set -eu

# shellcheck disable=SC2034 # Consumed by the test file that sources this helper.
TEST_ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'not ok - %s\n' "$1" >&2; }

assert_eq() {
    name=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then pass "$name"; else fail "$name (expected '$expected', got '$actual')"; fi
}

assert_file_contains() {
    name=$1 file=$2 pattern=$3
    if grep -F -- "$pattern" "$file" >/dev/null 2>&1; then pass "$name"; else fail "$name ($pattern not in $file)"; fi
}

assert_not_contains() {
    name=$1 file=$2 pattern=$3
    if grep -F -- "$pattern" "$file" >/dev/null 2>&1; then fail "$name (unexpected $pattern in $file)"; else pass "$name"; fi
}

finish() {
    printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ]
}
