#!/bin/bash

set -euo pipefail

# ====== 1. Application constants and defaults ================================

readonly APP_NAME="obsidian-vault-backup"
readonly APP_DIR="$HOME/config/$APP_NAME"
readonly SETTINGS_FILE="$APP_DIR/settings.sh"
readonly KOPIA_CONFIG_FILE="$APP_DIR/repository.config"
readonly LOG_FILE="$APP_DIR/backup.log"
readonly LOCK_DIR="$APP_DIR/backup.lock"
readonly INSTALLED_SCRIPT="$APP_DIR/$APP_NAME.sh"
readonly LAUNCHD_LABEL="com.example.obsidian-vault-backup"
readonly LAUNCHD_PLIST="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
readonly KEYCHAIN_SERVICE="$LAUNCHD_LABEL.kopia"
readonly KEYCHAIN_ACCOUNT="repository-password"
readonly DEFAULT_REMOTE_NAME="mega"
readonly DEFAULT_REMOTE_PATH="ObsidianVaultBackup"
readonly DEFAULT_INTERVAL_SECONDS=86400

SOURCE_PATH=""
REMOTE_NAME="$DEFAULT_REMOTE_NAME"
REMOTE_PATH="$DEFAULT_REMOTE_PATH"
MEGA_EMAIL=""
BACKUP_INTERVAL_SECONDS="$DEFAULT_INTERVAL_SECONDS"
KOPIA_BIN=""
RCLONE_BIN=""

CLI_SOURCE_PATH=""
CLI_INTERVAL_SECONDS=""
IMMEDIATE_BACKUP=true
UPDATE_SETTINGS=false
INSTALL_SCHEDULE=true
VERIFY_AFTER_BACKUP=false
SCHEDULED_RUN=false
FIRST_CONFIGURATION=false
REPOSITORY_CONNECTION_CHANGED=false


# ====== 2. Output, prompts, and validation ====================================

info() {
  printf '\n%s\n' "$*"
}

success() {
  printf '✓ %s\n' "$*"
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

prompt_value() {
  local prompt="$1"
  local default_value="${2:-}"
  local answer=""

  if [[ -n "$default_value" ]]; then
    printf '%s [%s]: ' "$prompt" "$default_value" >&2
  else
    printf '%s: ' "$prompt" >&2
  fi
  IFS= read -r answer
  printf '%s' "${answer:-$default_value}"
}

prompt_secret() {
  local prompt="$1"
  local answer=""
  printf '%s: ' "$prompt" >&2
  IFS= read -r -s answer
  printf '\n' >&2
  printf '%s' "$answer"
}

confirm() {
  local prompt="$1"
  local answer=""
  printf '%s [Y/n]: ' "$prompt" >&2
  IFS= read -r answer
  case "$answer" in
    ''|y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

confirm_no_default() {
  local prompt="$1"
  local answer=""
  printf '%s [y/N]: ' "$prompt" >&2
  IFS= read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

expand_home() {
  local value="$1"
  case "$value" in
    '~') printf '%s' "$HOME" ;;
    '~/'*) printf '%s/%s' "$HOME" "${value#\~/}" ;;
    *) printf '%s' "$value" ;;
  esac
}

validate_remote_name() {
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || die \
    "Remote name may contain only letters, numbers, underscores, and hyphens."
}

validate_interval() {
  [[ "$1" =~ ^[0-9]+$ ]] || die "Backup interval must be a number of seconds."
  (( "$1" >= 3600 )) || die "Backup interval must be at least 3600 seconds."
}

usage() {
  cat <<'EOF'
Obsidian Vault Backup for macOS

Usage:
  ./obsidian-vault-backup.sh [options]

Options:
  --source PATH          Use PATH as the source for this run only.
  --interval SECONDS     Override the launchd interval for this run only.
  --no-immediate-backup  Configure everything without starting a backup now.
  --no-schedule          Do not install or inspect the launchd schedule.
  --update-settings      Interactively update saved settings and credentials.
  --verify               Verify 100% of snapshot files after the backup.
  -h, --help             Show this help.

Saved settings and the installed script live in:
  ~/config/obsidian-vault-backup

Examples:
  ./obsidian-vault-backup.sh
  ./obsidian-vault-backup.sh --no-immediate-backup
  ./obsidian-vault-backup.sh --source /tmp/TestVault --no-schedule
  ./obsidian-vault-backup.sh --update-settings
EOF
}


# ====== 3. Command-line arguments ============================================

parse_arguments() {
  while (($#)); do
    case "$1" in
      --source)
        (($# >= 2)) || die "--source requires a path."
        CLI_SOURCE_PATH="$2"
        shift 2
        ;;
      --interval)
        (($# >= 2)) || die "--interval requires a number of seconds."
        CLI_INTERVAL_SECONDS="$2"
        shift 2
        ;;
      --no-immediate-backup)
        IMMEDIATE_BACKUP=false
        shift
        ;;
      --no-schedule)
        INSTALL_SCHEDULE=false
        shift
        ;;
      --update-settings)
        UPDATE_SETTINGS=true
        shift
        ;;
      --verify)
        VERIFY_AFTER_BACKUP=true
        shift
        ;;
      --scheduled-run)
        SCHEDULED_RUN=true
        INSTALL_SCHEDULE=false
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1. Run with --help to see available options."
        ;;
    esac
  done
}


# ====== 4. macOS and Homebrew dependencies ===================================

add_homebrew_to_path() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    PATH="/opt/homebrew/bin:$PATH"
  elif [[ -x /usr/local/bin/brew ]]; then
    PATH="/usr/local/bin:$PATH"
  fi
  export PATH
}

install_homebrew_if_needed() {
  command -v brew >/dev/null 2>&1 && return 0

  [[ "$SCHEDULED_RUN" == false ]] || die "Homebrew is not installed. Run the script manually first."
  confirm "Homebrew is required to install backup tools. Install it now?" || \
    die "Homebrew is required. Install it from https://brew.sh and run this script again."

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  add_homebrew_to_path
  command -v brew >/dev/null 2>&1 || die \
    "Homebrew was installed but is not on PATH. Restart Terminal and rerun the script."
}

install_cli_tools_if_needed() {
  local missing=()

  command -v kopia >/dev/null 2>&1 || missing+=(kopia)
  command -v rclone >/dev/null 2>&1 || missing+=(rclone)
  ((${#missing[@]} == 0)) && return 0

  [[ "$SCHEDULED_RUN" == false ]] || die \
    "Required utilities are missing: ${missing[*]}. Run the script manually first."

  confirm "Install the missing utilities with Homebrew (${missing[*]})?" || \
    die "Cannot continue without: ${missing[*]}"
  brew install "${missing[@]}"
}

offer_kopia_ui() {
  [[ "$SCHEDULED_RUN" == false ]] || return 0
  [[ "$FIRST_CONFIGURATION" == true ]] || return 0
  [[ -d /Applications/KopiaUI.app || -d "$HOME/Applications/KopiaUI.app" ]] && return 0

  if confirm "Install KopiaUI for visual browsing and restores?"; then
    brew install --cask kopiaui
  else
    warn "KopiaUI was skipped. You can install it later with: brew install --cask kopiaui"
  fi
}

ensure_dependencies() {
  [[ "$(uname -s)" == Darwin ]] || die "This script supports macOS only."
  command -v security >/dev/null 2>&1 || die "macOS security utility was not found."
  command -v curl >/dev/null 2>&1 || die "curl was not found."

  add_homebrew_to_path
  install_homebrew_if_needed
  install_cli_tools_if_needed

  KOPIA_BIN="$(command -v kopia)"
  RCLONE_BIN="$(command -v rclone)"
  offer_kopia_ui
}


# ====== 5. Persistent application files and settings =========================

install_script_copy() {
  local source_file="${BASH_SOURCE[0]:-}"

  mkdir -p "$APP_DIR"
  chmod 700 "$APP_DIR"

  if [[ -n "$source_file" && -f "$source_file" ]]; then
    if [[ "$(cd "$(dirname "$source_file")" && pwd)/$(basename "$source_file")" != "$INSTALLED_SCRIPT" ]]; then
      cp "$source_file" "$INSTALLED_SCRIPT"
      chmod 700 "$INSTALLED_SCRIPT"
      success "Installed a runnable copy at $INSTALLED_SCRIPT"
    fi
  elif [[ ! -x "$INSTALLED_SCRIPT" ]]; then
    die "Download the script to a file before running it so it can install a persistent copy."
  fi
}

load_settings() {
  [[ -f "$SETTINGS_FILE" ]] || return 1
  # The file is generated by this script and readable only by the current user.
  # shellcheck disable=SC1090
  source "$SETTINGS_FILE"
}

save_settings() {
  local temporary_file="$SETTINGS_FILE.tmp"
  umask 077
  {
    printf '# Generated by %s. Do not add passwords to this file.\n' "$APP_NAME"
    printf 'SOURCE_PATH=%q\n' "$SOURCE_PATH"
    printf 'REMOTE_NAME=%q\n' "$REMOTE_NAME"
    printf 'REMOTE_PATH=%q\n' "$REMOTE_PATH"
    printf 'MEGA_EMAIL=%q\n' "$MEGA_EMAIL"
    printf 'BACKUP_INTERVAL_SECONDS=%q\n' "$BACKUP_INTERVAL_SECONDS"
  } > "$temporary_file"
  mv "$temporary_file" "$SETTINGS_FILE"
  chmod 600 "$SETTINGS_FILE"
  success "Settings saved to $SETTINGS_FILE"
  printf '  Repository passwords are stored in macOS Keychain, not in this file.\n'
}

configure_rclone_remote() {
  local mega_password="$1"
  local obscured_password=""
  local remote_exists=false

  "$RCLONE_BIN" listremotes 2>/dev/null | \
    grep -Fxq "${REMOTE_NAME}:" && remote_exists=true

  if [[ -z "$mega_password" ]]; then
    [[ "$remote_exists" == true ]] || die "A MEGA password is required for a new remote."
    "$RCLONE_BIN" config update \
      "$REMOTE_NAME" user "$MEGA_EMAIL" --no-output
  else
    obscured_password="$(printf '%s\n' "$mega_password" | "$RCLONE_BIN" obscure -)"
    if [[ "$remote_exists" == true ]]; then
      "$RCLONE_BIN" config update \
        "$REMOTE_NAME" user "$MEGA_EMAIL" pass "$obscured_password" \
        --no-obscure --no-output
    else
      "$RCLONE_BIN" config create \
        "$REMOTE_NAME" mega user "$MEGA_EMAIL" pass "$obscured_password" \
        --no-obscure --no-output
    fi
  fi
  unset mega_password obscured_password
}

configure_settings_interactively() {
  local old_remote_spec="${REMOTE_NAME}:${REMOTE_PATH}"
  local source_input=""
  local interval_input=""
  local mega_password=""
  local remote_already_exists=false

  info "Configuration"
  printf 'Settings will be stored in: %s\n' "$SETTINGS_FILE"
  printf 'Your Kopia password will be stored in macOS Keychain.\n'
  printf 'The rclone file contains an obscured (not strongly encrypted) MEGA password and is readable only by your macOS account.\n\n'

  while :; do
    source_input="$(prompt_value "Folder to back up" "$SOURCE_PATH")"
    SOURCE_PATH="$(expand_home "$source_input")"
    [[ -d "$SOURCE_PATH" ]] && break
    warn "Folder does not exist: $SOURCE_PATH"
  done

  REMOTE_NAME="$(prompt_value "rclone remote name" "$REMOTE_NAME")"
  validate_remote_name "$REMOTE_NAME"
  REMOTE_PATH="$(prompt_value "Folder in MEGA for the encrypted repository" "$REMOTE_PATH")"
  [[ -n "$REMOTE_PATH" ]] || die "Remote path cannot be empty."
  MEGA_EMAIL="$(prompt_value "MEGA account email" "$MEGA_EMAIL")"
  [[ -n "$MEGA_EMAIL" ]] || die "MEGA email cannot be empty."

  "$RCLONE_BIN" listremotes 2>/dev/null | \
    grep -Fxq "${REMOTE_NAME}:" && remote_already_exists=true
  if [[ "$remote_already_exists" == true ]]; then
    if confirm_no_default "Update the saved MEGA password?"; then
      mega_password="$(prompt_secret "MEGA password")"
      [[ -n "$mega_password" ]] || die "MEGA password cannot be empty."
    fi
  else
    mega_password="$(prompt_secret "MEGA password")"
    [[ -n "$mega_password" ]] || die "MEGA password cannot be empty."
  fi

  interval_input="$(prompt_value "Backup interval in seconds" "$BACKUP_INTERVAL_SECONDS")"
  validate_interval "$interval_input"
  BACKUP_INTERVAL_SECONDS="$interval_input"

  configure_rclone_remote "$mega_password"
  unset mega_password
  save_settings
  "$RCLONE_BIN" config file

  if [[ -f "$KOPIA_CONFIG_FILE" && "$old_remote_spec" != "${REMOTE_NAME}:${REMOTE_PATH}" ]]; then
    REPOSITORY_CONNECTION_CHANGED=true
  fi

  if keychain_password >/dev/null 2>&1; then
    if confirm_no_default "Replace the Kopia repository password stored in Keychain?"; then
      printf 'This changes only the local Keychain copy; enter the password that the repository already uses.\n'
      prompt_and_store_repository_password
    fi
  fi
}

apply_cli_overrides() {
  if [[ -n "$CLI_SOURCE_PATH" ]]; then
    SOURCE_PATH="$(expand_home "$CLI_SOURCE_PATH")"
  fi
  if [[ -n "$CLI_INTERVAL_SECONDS" ]]; then
    validate_interval "$CLI_INTERVAL_SECONDS"
    BACKUP_INTERVAL_SECONDS="$CLI_INTERVAL_SECONDS"
  fi
}

validate_effective_settings() {
  [[ -n "$SOURCE_PATH" ]] || die "Source path is empty. Run with --update-settings."
  [[ -d "$SOURCE_PATH" ]] || die "Source folder does not exist: $SOURCE_PATH"
  validate_remote_name "$REMOTE_NAME"
  [[ -n "$REMOTE_PATH" ]] || die "Remote path is empty."
  validate_interval "$BACKUP_INTERVAL_SECONDS"
  "$RCLONE_BIN" listremotes 2>/dev/null | grep -Fxq "${REMOTE_NAME}:" || \
    die "rclone remote '${REMOTE_NAME}' is missing. Run with --update-settings."
}


# ====== 6. Keychain and Kopia repository =====================================

keychain_password() {
  security find-generic-password \
    -s "$KEYCHAIN_SERVICE" \
    -a "$KEYCHAIN_ACCOUNT" \
    -w
}

prompt_and_store_repository_password() {
  local password=""
  local confirmation=""

  password="$(prompt_secret "Kopia repository password")"
  confirmation="$(prompt_secret "Confirm Kopia repository password")"
  [[ -n "$password" ]] || die "Kopia password cannot be empty."
  [[ "$password" == "$confirmation" ]] || die "Kopia passwords do not match."

  security add-generic-password -U \
    -s "$KEYCHAIN_SERVICE" \
    -a "$KEYCHAIN_ACCOUNT" \
    -w "$password" >/dev/null
  unset password confirmation
  success "Kopia password stored in macOS Keychain"
}

ensure_repository_password() {
  if ! keychain_password >/dev/null 2>&1; then
    [[ "$SCHEDULED_RUN" == false ]] || die \
      "Kopia password is missing from Keychain. Run the script manually."
    info "Create or enter the password for the encrypted Kopia repository."
    printf 'Save the same password in Apple Passwords: losing it makes recovery impossible.\n'
    prompt_and_store_repository_password
  fi
}

kopia_run() {
  KOPIA_PASSWORD="$(keychain_password)" "$KOPIA_BIN" \
    --config-file="$KOPIA_CONFIG_FILE" "$@"
}

repository_remote_spec() {
  printf '%s:%s' "$REMOTE_NAME" "$REMOTE_PATH"
}

connect_or_create_repository() {
  local action=""

  info "Kopia repository"
  printf 'Remote location: %s\n' "$(repository_remote_spec)"
  action="$(prompt_value "Create a new repository or connect to an existing one? (create/connect)" "create")"

  case "$action" in
    create|c|C)
      kopia_run repository create rclone \
        --rclone-exe="$RCLONE_BIN" \
        --remote-path="$(repository_remote_spec)"
      ;;
    connect|e|E)
      kopia_run repository connect rclone \
        --rclone-exe="$RCLONE_BIN" \
        --remote-path="$(repository_remote_spec)"
      ;;
    *)
      die "Choose either 'create' or 'connect'."
      ;;
  esac
}

ensure_repository_connection() {
  local backup_config=""

  ensure_repository_password

  if [[ "$REPOSITORY_CONNECTION_CHANGED" == true && -f "$KOPIA_CONFIG_FILE" ]]; then
    backup_config="$KOPIA_CONFIG_FILE.previous.$(date '+%Y%m%d%H%M%S')"
    mv "$KOPIA_CONFIG_FILE" "$backup_config"
    warn "Remote repository changed. Previous Kopia connection saved at $backup_config"
  fi

  if [[ -f "$KOPIA_CONFIG_FILE" ]] && kopia_run repository status >/dev/null 2>&1; then
    success "Connected to the existing Kopia repository"
  else
    [[ "$SCHEDULED_RUN" == false ]] || die \
      "Kopia repository is not connected. Run the script manually."
    [[ -f "$KOPIA_CONFIG_FILE" ]] && mv \
      "$KOPIA_CONFIG_FILE" "$KOPIA_CONFIG_FILE.invalid.$(date '+%Y%m%d%H%M%S')"
    connect_or_create_repository
  fi

  kopia_run policy set --global \
    --manual \
    --keep-latest=0 \
    --keep-daily=14 \
    --keep-weekly=8 \
    --keep-monthly=12 \
    --ignore-identical-snapshots >/dev/null
  success "Retention policy is active: 14 daily, 8 weekly, 12 monthly"
}


# ====== 7. Immediate and scheduled backup ====================================

acquire_backup_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    die "Another backup appears to be running. If it is not, remove $LOCK_DIR"
  fi
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
}

run_backup() {
  acquire_backup_lock
  info "Starting encrypted backup"
  printf 'Source: %s\n' "$SOURCE_PATH"
  printf 'Destination: %s\n' "$(repository_remote_spec)"

  kopia_run snapshot create "$SOURCE_PATH"
  success "Backup completed at $(date '+%Y-%m-%d %H:%M:%S')"

  if [[ "$VERIFY_AFTER_BACKUP" == true ]]; then
    info "Verifying all files in the repository"
    kopia_run snapshot verify --verify-files-percent=100
    success "Repository verification completed"
  fi
}


# ====== 8. launchd schedule ===================================================

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "$value"
}

write_launchd_plist() {
  local script_xml=""
  local log_xml=""
  script_xml="$(xml_escape "$INSTALLED_SCRIPT")"
  log_xml="$(xml_escape "$LOG_FILE")"

  mkdir -p "$HOME/Library/LaunchAgents"
  umask 077
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0">'
    printf '%s\n' '<dict>'
    printf '  <key>Label</key><string>%s</string>\n' "$LAUNCHD_LABEL"
    printf '  <key>ProgramArguments</key><array><string>%s</string><string>--scheduled-run</string></array>\n' "$script_xml"
    printf '  <key>StartInterval</key><integer>%s</integer>\n' "$BACKUP_INTERVAL_SECONDS"
    printf '  <key>StandardOutPath</key><string>%s</string>\n' "$log_xml"
    printf '  <key>StandardErrorPath</key><string>%s</string>\n' "$log_xml"
    printf '%s\n' '</dict>'
    printf '%s\n' '</plist>'
  } > "$LAUNCHD_PLIST"
  chmod 600 "$LAUNCHD_PLIST"
  plutil -lint "$LAUNCHD_PLIST" >/dev/null
}

schedule_matches() {
  local installed_interval=""
  local installed_script=""
  [[ -f "$LAUNCHD_PLIST" ]] || return 1
  installed_interval="$(plutil -extract StartInterval raw "$LAUNCHD_PLIST" 2>/dev/null || true)"
  installed_script="$(plutil -extract ProgramArguments.0 raw "$LAUNCHD_PLIST" 2>/dev/null || true)"
  [[ "$installed_interval" == "$BACKUP_INTERVAL_SECONDS" && "$installed_script" == "$INSTALLED_SCRIPT" ]]
}

ensure_schedule() {
  local domain="gui/$(id -u)"
  local service="$domain/$LAUNCHD_LABEL"

  if schedule_matches && launchctl print "$service" >/dev/null 2>&1; then
    success "Backup schedule is already installed; no duplicate was created"
    return 0
  fi

  write_launchd_plist
  launchctl bootout "$service" >/dev/null 2>&1 || true
  launchctl bootstrap "$domain" "$LAUNCHD_PLIST"
  success "Backup schedule installed: every $BACKUP_INTERVAL_SECONDS seconds"
}


# ====== 9. Main flow ==========================================================

main() {
  parse_arguments "$@"
  mkdir -p "$APP_DIR"
  chmod 700 "$APP_DIR"

  if [[ "$SCHEDULED_RUN" == true ]]; then
    load_settings || die "Settings are missing: $SETTINGS_FILE"
    add_homebrew_to_path
    KOPIA_BIN="$(command -v kopia || true)"
    RCLONE_BIN="$(command -v rclone || true)"
    [[ -x "$KOPIA_BIN" && -x "$RCLONE_BIN" ]] || die \
      "kopia or rclone is missing. Run the script manually."
    validate_effective_settings
    ensure_repository_connection
    run_backup
    exit 0
  fi

  [[ -f "$SETTINGS_FILE" ]] || FIRST_CONFIGURATION=true
  load_settings || true
  install_script_copy
  ensure_dependencies

  if [[ "$FIRST_CONFIGURATION" == true || "$UPDATE_SETTINGS" == true ]]; then
    configure_settings_interactively
  fi

  load_settings || die "Settings are missing: $SETTINGS_FILE"
  apply_cli_overrides
  validate_effective_settings
  ensure_repository_connection

  if [[ "$IMMEDIATE_BACKUP" == true ]]; then
    run_backup
  else
    info "Immediate backup skipped by --no-immediate-backup."
  fi

  if [[ "$INSTALL_SCHEDULE" == true ]]; then
    ensure_schedule
  fi

  info "Setup complete"
  printf 'Settings: %s\n' "$SETTINGS_FILE"
  printf 'Logs: %s\n' "$LOG_FILE"
  printf 'Run again at any time: %s\n' "$INSTALLED_SCRIPT"
  printf 'Update settings: %s --update-settings\n' "$INSTALLED_SCRIPT"
  printf 'KopiaUI rclone executable: %s\n' "$RCLONE_BIN"
  printf 'KopiaUI remote path: %s\n' "$(repository_remote_spec)"
}

main "$@"
