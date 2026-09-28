#!/bin/sh

. "$(dirname "$0")/test_helper.sh"
. "$TEST_ROOT/scripts/common.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

cat >"$tmp/good.env" <<'EOF'
# comment
HOST_ID=app-01
OBSERVABILITY_PASSWORD=a value with spaces
EMPTY=
EOF

config_parse "$tmp/good.env" 'HOST_ID OBSERVABILITY_PASSWORD EMPTY' "$tmp/parsed"
assert_eq 'reads a known key' 'app-01' "$(config_get "$tmp/parsed" HOST_ID)"
assert_eq 'preserves value text' 'a value with spaces' "$(config_get "$tmp/parsed" OBSERVABILITY_PASSWORD)"

cat >"$tmp/evil.env" <<EOF
HOST_ID=\$(touch "$tmp/pwned")
EOF
config_parse "$tmp/evil.env" 'HOST_ID' "$tmp/evil-parsed"
assert_eq 'never executes config values' 'no' "$([ -e "$tmp/pwned" ] && echo yes || echo no)"

printf 'UNKNOWN=value\n' >"$tmp/unknown.env"
if config_parse "$tmp/unknown.env" 'HOST_ID' "$tmp/out" 2>/dev/null; then fail 'rejects unknown keys'; else pass 'rejects unknown keys'; fi

printf 'HOST_ID=a\nHOST_ID=b\n' >"$tmp/duplicate.env"
if config_parse "$tmp/duplicate.env" 'HOST_ID' "$tmp/out" 2>/dev/null; then fail 'rejects duplicate keys'; else pass 'rejects duplicate keys'; fi

assert_eq 'sanitizes Alloy identifiers' 'shop_eu_1' "$(alloy_identifier 'Shop-EU.1')"
if validate_open_ports '3000,8000-8999'; then pass 'accepts bounded Beyla ports'; else fail 'accepts bounded Beyla ports'; fi
if validate_open_ports '1-65535'; then fail 'rejects all-port Beyla discovery'; else pass 'rejects all-port Beyla discovery'; fi

finish
