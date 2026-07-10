#!/bin/bash

set -o nounset
set -o pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CONFIG_FILE="$PROJECT_ROOT/config/local.env"
readonly APP_SUPPORT_DIR="$HOME/Library/Application Support/ObsidianVaultBackup"
readonly KOPIA_CONFIG_FILE="$APP_SUPPORT_DIR/repository.config"
readonly LOG_DIR="$PROJECT_ROOT/logs"

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

load_config() {
  [[ -f "$CONFIG_FILE" ]] || die "Missing $CONFIG_FILE. Copy config/backup.env.example first."
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"

  [[ -n "${BACKUP_SOURCE:-}" ]] || die "BACKUP_SOURCE is empty in $CONFIG_FILE"
  [[ -n "${RCLONE_REMOTE_NAME:-}" ]] || die "RCLONE_REMOTE_NAME is empty in $CONFIG_FILE"
  [[ -n "${RCLONE_REMOTE_PATH:-}" ]] || die "RCLONE_REMOTE_PATH is empty in $CONFIG_FILE"
  [[ -n "${KEYCHAIN_SERVICE:-}" ]] || die "KEYCHAIN_SERVICE is empty in $CONFIG_FILE"
  [[ -n "${KEYCHAIN_ACCOUNT:-}" ]] || die "KEYCHAIN_ACCOUNT is empty in $CONFIG_FILE"
}

get_repository_password() {
  security find-generic-password \
    -s "$KEYCHAIN_SERVICE" \
    -a "$KEYCHAIN_ACCOUNT" \
    -w
}

kopia() {
  KOPIA_PASSWORD="$(get_repository_password)" command kopia \
    --config-file="$KOPIA_CONFIG_FILE" "$@"
}

remote_path() {
  printf '%s:%s' "$RCLONE_REMOTE_NAME" "$RCLONE_REMOTE_PATH"
}

