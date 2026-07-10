#!/bin/bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

require_command security
require_command kopia
load_config
[[ -f "$KOPIA_CONFIG_FILE" ]] || die "No connected Kopia repository. Run scripts/setup.sh --create-repository first."

kopia snapshot verify --verify-files-percent=100

