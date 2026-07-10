#!/bin/bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

require_command security
require_command rclone
require_command kopia
load_config
[[ -d "$BACKUP_SOURCE" ]] || die "BACKUP_SOURCE does not exist: $BACKUP_SOURCE"
[[ -f "$KOPIA_CONFIG_FILE" ]] || die "No connected Kopia repository. Run scripts/setup.sh --create-repository first."

mkdir -p "$LOG_DIR"
readonly LOCK_DIRECTORY="$LOG_DIR/backup.lock"
if ! mkdir "$LOCK_DIRECTORY" 2>/dev/null; then
  printf 'A backup is already running; skipping this invocation.\n'
  exit 0
fi
trap 'rmdir "$LOCK_DIRECTORY"' EXIT

printf '[%s] Starting backup of %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$BACKUP_SOURCE"
kopia snapshot create "$BACKUP_SOURCE"
printf '[%s] Backup completed successfully.\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
