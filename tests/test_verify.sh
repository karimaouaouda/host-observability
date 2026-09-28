#!/bin/sh

. "$(dirname "$0")/test_helper.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cp -R "$TEST_ROOT/." "$tmp/project"
cp "$tmp/project/.env.example" "$tmp/project/.env"
sed -i 's/CHANGE_ME/test-secret/' "$tmp/project/.env"
sed -i 's/ENABLE_DOCKER_METRICS=true/ENABLE_DOCKER_METRICS=false/' "$tmp/project/.env"
sed -i 's/ENABLE_DOCKER_LOGS=true/ENABLE_DOCKER_LOGS=false/' "$tmp/project/.env"
sed -i 's/ENABLE_NGINX_LOGS=true/ENABLE_NGINX_LOGS=false/' "$tmp/project/.env"
mkdir "$tmp/bin"

cat >"$tmp/bin/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$tmp/bin/curl" <<'EOF'
#!/bin/sh
case "$*" in
    *127.0.0.1:12345*)
        count=0
        [ ! -f "$VERIFY_COUNTER_FILE" ] || count=$(sed -n '1p' "$VERIFY_COUNTER_FILE")
        count=$((count + 1))
        printf '%s\n' "$count" >"$VERIFY_COUNTER_FILE"
        [ "$count" -ge 3 ]
        ;;
    *)
        printf '400'
        ;;
esac
EOF
cat >"$tmp/bin/journalctl" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$tmp/bin/systemctl" "$tmp/bin/curl" "$tmp/bin/journalctl"

if PATH="$tmp/bin:$PATH" PROJECT_ROOT="$tmp/project" VERIFY_COUNTER_FILE="$tmp/counter" \
    VERIFY_TIMEOUT_SECONDS=5 VERIFY_RETRY_INTERVAL_SECONDS=0 sh "$tmp/project/scripts/verify.sh" >"$tmp/output" 2>&1; then
    pass 'verification retries until Alloy HTTP endpoints are available'
else
    fail 'verification retries until Alloy HTTP endpoints are available'
    sed -n '1,160p' "$tmp/output" >&2
fi
assert_file_contains 'reports readiness after retry' "$tmp/output" 'Alloy ready endpoint passed'
assert_file_contains 'reports health after retry' "$tmp/output" 'Alloy healthy endpoint passed'

finish
