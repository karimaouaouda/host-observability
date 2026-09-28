#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"
require_root

export DEBIAN_FRONTEND=noninteractive
info 'Installing minimal operating-system dependencies'
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg acl libcap2-bin

if command_exists alloy; then
    ok "Grafana Alloy is already installed: $(alloy --version 2>/dev/null | head -1)"
    exit 0
fi

info 'Adding the official Grafana APT repository'
install -d -m 0755 /etc/apt/keyrings
key_tmp=$(mktemp)
trap 'rm -f "$key_tmp"' EXIT HUP INT TERM
curl -fsSL https://apt.grafana.com/gpg-full.key -o "$key_tmp"
install -m 0644 "$key_tmp" /etc/apt/keyrings/grafana.asc
printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main' >/etc/apt/sources.list.d/grafana.list
apt-get update
apt-get install -y --no-install-recommends alloy
ok "Installed Grafana Alloy: $(alloy --version 2>/dev/null | head -1)"
