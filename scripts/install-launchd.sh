#!/bin/bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

require_command launchctl
require_command plutil
load_config
[[ -f "$KOPIA_CONFIG_FILE" ]] || die "No connected Kopia repository. Complete the acceptance test first."

readonly LABEL="com.example.obsidian-vault-backup"
readonly PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
readonly TEMPLATE="$PROJECT_ROOT/launchd/$LABEL.plist.template"

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"
cp "$TEMPLATE" "$PLIST_PATH"
plutil -replace 'ProgramArguments.0' -string "$PROJECT_ROOT/scripts/run-backup.sh" "$PLIST_PATH"
plutil -replace StandardOutPath -string "$LOG_DIR/launchd.log" "$PLIST_PATH"
plutil -replace StandardErrorPath -string "$LOG_DIR/launchd.log" "$PLIST_PATH"
plutil -lint "$PLIST_PATH" >/dev/null

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
printf 'Installed %s. It runs at login and then every 24 hours.\n' "$LABEL"

