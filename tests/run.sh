#!/bin/sh

set -eu
cd "$(dirname "$0")/.."
failed=0
for test_file in tests/test_*.sh; do
    [ "$test_file" = tests/test_helper.sh ] && continue
    printf '\n# %s\n' "$test_file"
    sh "$test_file" || failed=1
done
exit "$failed"
