#!/usr/bin/env bash
# shellcheck shell=bash
# spectre-docker common library (sourced by setup.sh and modules)

if [[ -n "${SPECTRE_COMMON_LOADED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
SPECTRE_COMMON_LOADED=1

# Logging (TTY-safe colors)
if [[ -t 1 ]]; then
  _c_reset=$'\033[0m'; _c_red=$'\033[31m'; _c_green=$'\033[32m'; _c_yellow=$'\033[33m'; _c_blue=$'\033[34m'
else
  _c_reset=''; _c_red=''; _c_green=''; _c_yellow=''; _c_blue=''
fi

log_info()  { printf '%s[INFO]%s %s\n' "$_c_blue" "$_c_reset" "$*"; }
log_warn()  { printf '%s[WARN]%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n' "$_c_red" "$_c_reset" "$*" >&2; }
log_ok()    { printf '%s[OK]%s %s\n' "$_c_green" "$_c_reset" "$*"; }

die() {
  log_error "$*"
  exit 1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "This script must be run as root (try: sudo ./setup.sh)"
  fi
}

# OS detection
export SPECTRE_OS_ID=""
export SPECTRE_OS_ID_LIKE=""
export SPECTRE_OS_VERSION_ID=""
export SPECTRE_OS_CODENAME=""

detect_os() {
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release; unsupported system."
  # shellcheck disable=SC1091
  . /etc/os-release
  SPECTRE_OS_ID="${ID:-}"
  SPECTRE_OS_ID_LIKE="${ID_LIKE:-}"
  SPECTRE_OS_VERSION_ID="${VERSION_ID:-}"
  SPECTRE_OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
}

assert_supported_os() {
  detect_os
  case "${SPECTRE_OS_ID}" in
    ubuntu|debian) ;;
    *)
      # allow derivatives that identify as ubuntu/debian-like only if explicit ID matches via ID_LIKE? be conservative
      if [[ " ${SPECTRE_OS_ID_LIKE} " == *" debian "* || " ${SPECTRE_OS_ID_LIKE} " == *" ubuntu "* ]]; then
        log_warn "Detected derivative OS '${SPECTRE_OS_ID}' (ID_LIKE='${SPECTRE_OS_ID_LIKE}'); proceeding on a best-effort basis."
      else
        die "Unsupported OS '${SPECTRE_OS_ID}'. spectre-docker supports Ubuntu and Debian only."
      fi
      ;;
  esac
  command -v apt-get >/dev/null 2>&1 || die "apt-get not found; supported Ubuntu/Debian systems are required."
}

# Safe config loading: parse KEY=VALUE without executing file
# Sets allowed variables and applies defaults/validation hooks in setup.
load_config() {
  local conf="$1"
  [[ -f "$conf" ]] || die "Config file not found: $conf"
  [[ -r "$conf" ]] || die "Config file not readable: $conf"

  local line key val lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno+1))
    # strip CR
    line=${line%$'\r'}
    # skip blank/comments
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^[[:space:]]*([A-Z0-9_]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      # trim leading/trailing whitespace in val
      val="${val#"${val%%[![:space:]]*}"}"
      val="${val%"${val##*[![:space:]]}"}"
      # strip surrounding quotes if paired
      if [[ "$val" =~ ^\"(.*)\"$ ]]; then
        val="${BASH_REMATCH[1]}"
      elif [[ "$val" =~ ^\'(.*)\'$ ]]; then
        val="${BASH_REMATCH[1]}"
      fi
      case "$key" in
        ADMIN_USER|ADMIN_SSH_PUBLIC_KEYS|SSH_PORT|SSH_PASSWORD_AUTH|SSH_PERMIT_ROOT_LOGIN|SSH_PUBKEY_AUTH|UFW_ALLOWED_TCP_PORTS|BACKUP_ENABLED|BACKUP_TARGET_DIR|BACKUP_PATHS|BACKUP_RETENTION_COUNT|BACKUP_SCHEDULE|ALLOW_LOCKOUT_RISK)
          printf -v "$key" '%s' "$val"
          ;;
        *)
          log_warn "Ignoring unknown config key '$key' at ${conf}:${lineno}"
          ;;
      esac
    else
      die "Invalid config syntax at ${conf}:${lineno} (expected KEY=VALUE)"
    fi
  done < "$conf"
}

# Defaults and validation
apply_config_defaults() {
  : "${ADMIN_USER:=deploy}"
  : "${ADMIN_SSH_PUBLIC_KEYS:=}"
  : "${SSH_PORT:=22}"
  : "${SSH_PASSWORD_AUTH:=no}"
  : "${SSH_PERMIT_ROOT_LOGIN:=no}"
  : "${SSH_PUBKEY_AUTH:=yes}"
  : "${UFW_ALLOWED_TCP_PORTS:=}"
  : "${BACKUP_ENABLED:=yes}"
  : "${BACKUP_TARGET_DIR:=/var/backups/spectre-docker}"
  : "${BACKUP_PATHS:=/etc /etc/spectre-docker}"
  : "${BACKUP_RETENTION_COUNT:=7}"
  : "${BACKUP_SCHEDULE:=daily}"
  : "${ALLOW_LOCKOUT_RISK:=no}"

  # normalize booleans-ish to lowercase
  SSH_PASSWORD_AUTH="${SSH_PASSWORD_AUTH,,}"
  SSH_PERMIT_ROOT_LOGIN="${SSH_PERMIT_ROOT_LOGIN,,}"
  SSH_PUBKEY_AUTH="${SSH_PUBKEY_AUTH,,}"
  BACKUP_ENABLED="${BACKUP_ENABLED,,}"
  ALLOW_LOCKOUT_RISK="${ALLOW_LOCKOUT_RISK,,}"
}

validate_config() {
  [[ "$ADMIN_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || die "ADMIN_USER '$ADMIN_USER' is not a valid username."
  if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
    die "SSH_PORT must be a valid port number."
  fi
  [[ "$BACKUP_RETENTION_COUNT" =~ ^[0-9]+$ ]] || die "BACKUP_RETENTION_COUNT must be a non-negative integer."
  case "$SSH_PASSWORD_AUTH" in yes|no) ;; *) die "SSH_PASSWORD_AUTH must be 'yes' or 'no'.";; esac
  case "$SSH_PERMIT_ROOT_LOGIN" in yes|no|prohibit-password|forced-commands-only) ;; *) die "SSH_PERMIT_ROOT_LOGIN must be yes|no|prohibit-password|forced-commands-only.";; esac
  case "$SSH_PUBKEY_AUTH" in yes|no) ;; *) die "SSH_PUBKEY_AUTH must be 'yes' or 'no'.";; esac
  case "$BACKUP_ENABLED" in yes|no) ;; *) die "BACKUP_ENABLED must be 'yes' or 'no'.";; esac
  case "$ALLOW_LOCKOUT_RISK" in yes|no) ;; *) die "ALLOW_LOCKOUT_RISK must be 'yes' or 'no'.";; esac
}

# Lockout safety: if password auth disabled, ensure some admin key path is viable unless override
check_lockout_safety() {
  if [[ "$SSH_PASSWORD_AUTH" == "no" && "$ALLOW_LOCKOUT_RISK" != "yes" ]]; then
    local has_key=0
    if [[ -n "$ADMIN_SSH_PUBLIC_KEYS" ]]; then
      if [[ -f "$ADMIN_SSH_PUBLIC_KEYS" && -s "$ADMIN_SSH_PUBLIC_KEYS" ]]; then
        has_key=1
      elif [[ "$ADMIN_SSH_PUBLIC_KEYS" =~ ^ssh- || "$ADMIN_SSH_PUBLIC_KEYS" =~ ^ecdsa- ]]; then
        has_key=1
      fi
    fi
    # also accept existing authorized_keys for admin user
    if [[ $has_key -eq 0 ]] && id "$ADMIN_USER" >/dev/null 2>&1; then
      local home_dir
      home_dir="$(getent passwd "$ADMIN_USER" | cut -d: -f6 || true)"
      if [[ -n "$home_dir" && -s "$home_dir/.ssh/authorized_keys" ]]; then
        has_key=1
      fi
    fi
    if [[ $has_key -eq 0 ]]; then
      die "Lockout safety: SSH_PASSWORD_AUTH=no but no ADMIN_SSH_PUBLIC_KEYS configured/found and no existing authorized_keys for '${ADMIN_USER}'. Provide a public key or set ALLOW_LOCKOUT_RISK=yes to override intentionally."
    fi
  fi
}

# Utility helpers
command_exists() { command -v "$1" >/dev/null 2>&1; }

apt_update_once() {
  if [[ -z "${_SPECTRE_APT_UPDATED:-}" ]]; then
    log_info "Updating apt package index..."
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    _SPECTRE_APT_UPDATED=1
  fi
}

ensure_packages() {
  local pkgs=("$@")
  local missing=()
  local p
  for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if (( ${#missing[@]} > 0 )); then
    apt_update_once
    log_info "Installing packages: ${missing[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
  else
    log_info "Packages already installed: ${pkgs[*]}"
  fi
}

write_file_if_changed() {
  # write_file_if_changed <dest> <mode> <owner:group or empty> <tmp_src_file>
  local dest="$1" mode="$2" owner="$3" src="$4"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
    return 1
  fi
  install -m "$mode" "$src" "$dest"
  if [[ -n "$owner" ]]; then
    chown "$owner" "$dest"
  fi
  return 0
}

ensure_line_in_file() {
  local line="$1" file="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

get_ssh_service_name() {
  if systemctl list-unit-files --type=service 2>/dev/null | grep -q '^ssh\.service'; then
    echo ssh
  else
    echo sshd
  fi
}
