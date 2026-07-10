#!/bin/bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

create_repository=false

usage() {
  cat <<'EOF'
Usage: scripts/setup.sh [--create-repository]

Initialises local configuration and stores the Kopia repository password in
macOS Keychain. --create-repository additionally creates the encrypted remote
repository and applies the backup policy. Use it only with a disposable source
directory until the acceptance test has passed.
EOF
}

while (($#)); do
  case "$1" in
    --create-repository) create_repository=true ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

require_command security
require_command rclone
require_command kopia
load_config

[[ -d "$BACKUP_SOURCE" ]] || die "BACKUP_SOURCE does not exist: $BACKUP_SOURCE"
mkdir -p "$APP_SUPPORT_DIR" "$LOG_DIR"

if ! rclone listremotes | grep -Fxq "${RCLONE_REMOTE_NAME}:"; then
  printf 'The rclone remote %q is missing.\n' "$RCLONE_REMOTE_NAME" >&2
  printf 'Create a MEGA remote with rclone config, then rerun this script.\n' >&2
  rclone config
  rclone listremotes | grep -Fxq "${RCLONE_REMOTE_NAME}:" || die "Remote is still missing."
fi

if ! get_repository_password >/dev/null 2>&1; then
  printf 'Create a new Kopia repository password. Save it in Apple Passwords too.\n' >&2
  read -r -s -p 'Kopia repository password: ' password
  printf '\n' >&2
  read -r -s -p 'Confirm password: ' confirmation
  printf '\n' >&2
  [[ -n "$password" ]] || die "Password cannot be empty."
  [[ "$password" == "$confirmation" ]] || die "Passwords do not match."
  security add-generic-password -U \
    -s "$KEYCHAIN_SERVICE" \
    -a "$KEYCHAIN_ACCOUNT" \
    -w "$password" >/dev/null
  unset password confirmation
fi

if [[ "$create_repository" == false ]]; then
  printf 'Prerequisites are ready. Run this command with --create-repository when ready to create the test repository.\n'
  exit 0
fi

if [[ -f "$KOPIA_CONFIG_FILE" ]]; then
  kopia repository status
  printf 'A Kopia repository is already connected; refusing to create another one.\n'
  exit 0
fi

kopia repository create rclone \
  --rclone-exe="$(command -v rclone)" \
  --remote-path="$(remote_path)"

kopia policy set "$BACKUP_SOURCE" \
  --manual \
  --keep-latest=0 \
  --keep-daily=14 \
  --keep-weekly=8 \
  --keep-monthly=12 \
  --ignore-identical-snapshots

printf 'Created and connected to the test repository at %s.\n' "$(remote_path)"

