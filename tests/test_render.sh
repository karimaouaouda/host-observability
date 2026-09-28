#!/bin/sh

. "$(dirname "$0")/test_helper.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cp -R "$TEST_ROOT/." "$tmp/project"
cd "$tmp/project" || exit 1
cp .env.example .env
sed -i 's/HOST_ID=my-vps-01/HOST_ID=test-vps/' .env
sed -i 's/OBSERVABILITY_PASSWORD=CHANGE_ME/OBSERVABILITY_PASSWORD=secret-pass/' .env
mkdir -p instances/postgres instances/mysql instances/redis
cat >instances/postgres/app.env <<'EOF'
NAME=app-db
DSN=postgresql://monitor:secret@127.0.0.1:15432/postgres?sslmode=disable
AUTODISCOVERY=true
APP=app
SERVICE=postgres
EOF
cat >instances/mysql/shop.env <<'EOF'
NAME=shop
DSN=monitor:secret@(127.0.0.1:13306)/
APP=shop
SERVICE=mysql
EOF
cat >instances/redis/cache.env <<'EOF'
NAME=cache
ADDRESS=127.0.0.1:16379
PASSWORD=redis-secret
APP=app
SERVICE=redis
EOF

out1=$tmp/out1 out2=$tmp/out2
PROJECT_ROOT=$PWD sh scripts/render-config.sh "$out1"
PROJECT_ROOT=$PWD sh scripts/render-config.sh "$out2"
if diff -ru "$out1" "$out2" >/dev/null; then pass 'rendering is deterministic'; else fail 'rendering is deterministic'; fi
assert_file_contains 'renders output endpoint' "$out1/10-outputs.alloy" 'sys.env("PROMETHEUS_WRITE_URL")'
assert_file_contains 'renders postgres component' "$out1/70-postgres-app_db.alloy" 'autodiscovery {'
assert_file_contains 'renders mysql component' "$out1/80-mysql-shop.alloy" 'prometheus.exporter.mysql "shop"'
assert_file_contains 'renders redis component' "$out1/90-redis-cache.alloy" 'redis_password = sys.env("REDIS_CACHE_PASSWORD")'
assert_not_contains 'does not embed central password' "$out1/10-outputs.alloy" 'secret-pass'
assert_not_contains 'does not embed database DSN' "$out1/70-postgres-app_db.alloy" 'monitor:secret'
assert_file_contains 'writes runtime DB secret' "$out1/agent.env" 'POSTGRES_APP_DB_DSN="postgresql://monitor:secret'
assert_file_contains 'binds local Alloy listener' "$out1/alloy.defaults" '--server.http.listen-addr=127.0.0.1:12345'

sed -i 's/OBSERVABILITY_AUTH_ENABLED=true/OBSERVABILITY_AUTH_ENABLED=false/' .env
sed -i 's#GRAFANA_URL=https://grafana.karimaouaouda.space#GRAFANA_URL=http://127.0.0.1:3000#' .env
sed -i 's#PROMETHEUS_WRITE_URL=https://observability.karimaouaouda.space/prometheus/write#PROMETHEUS_WRITE_URL=http://127.0.0.1:9090/api/v1/write#' .env
sed -i 's#LOKI_WRITE_URL=https://observability.karimaouaouda.space/loki/push#LOKI_WRITE_URL=http://127.0.0.1:3100/loki/api/v1/push#' .env
sed -i 's/TLS_INSECURE_SKIP_VERIFY=false/TLS_INSECURE_SKIP_VERIFY=true/' .env
out3=$tmp/out3
PROJECT_ROOT=$PWD sh scripts/render-config.sh "$out3"
assert_not_contains 'omits Basic Auth when disabled' "$out3/10-outputs.alloy" 'basic_auth'
assert_file_contains 'renders loopback TLS override' "$out3/10-outputs.alloy" 'insecure_skip_verify = true'

finish
