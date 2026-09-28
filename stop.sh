#!/bin/sh
set -eu
PROJECT_ROOT=${PROJECT_ROOT:-$(CDPATH='' cd -- "$(dirname "$0")" && pwd)}
. "$PROJECT_ROOT/scripts/common.sh"
require_root
systemctl stop alloy
ok 'Alloy stopped; package, configuration, and data were preserved.'
