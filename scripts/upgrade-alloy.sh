#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
PROJECT_ROOT=${PROJECT_ROOT:-$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)}
. "$SCRIPT_DIR/common.sh"
require_root
command_exists alloy || die 'Alloy is not installed; run start.sh first.'
before=$(alloy --version 2>/dev/null | head -1)
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --only-upgrade alloy
sh "$SCRIPT_DIR/configure-permissions.sh"
systemctl restart alloy
sh "$SCRIPT_DIR/verify.sh"
after=$(alloy --version 2>/dev/null | head -1)
ok "Alloy upgrade completed: $before -> $after"
