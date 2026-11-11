#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/spectre-docker/spectre-docker.conf"
BACKUP_ENABLED="yes"
BACKUP_TARGET_DIR="/var/backups/spectre-docker"
BACKUP_PATHS="/etc /etc/spectre-docker"
BACKUP_RETENTION_COUNT="7"
LOG_FILE="/var/log/spectre-docker-backup.log"

usage() {
  cat <<'EOF'
Usage: spectre-docker-backup [--config PATH] [--list] [--help]

Options:
  --config PATH  Path to spectre-docker config (default: /etc/spectre-docker/spectre-docker.conf)
  --list         List existing backup archives in BACKUP_TARGET_DIR and exit
  --help         Show this help
EOF
}

_ts() { date -Is; }
log() {
  local msg
  msg="[$(_ts)] $*"
  printf '%s\n' "$msg"
  printf '%s\n' "$msg" >> "$LOG_FILE" 2>/dev/null || true
}
err() {
  local msg
  msg="[$(_ts)] ERROR: $*"
  printf '%s\n' "$msg" >&2
  printf '%s\n' "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

load_conf() {
  local conf="$1"
  [[ -f "$conf" ]] || return 0
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^[[:space:]]*([A-Z0-9_]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      val="${val#"${val%%[![:space:]]*}"}"
      val="${val%"${val##*[![:space:]]}"}"
      if [[ "$val" =~ ^\"(.*)\"$ ]]; then val="${BASH_REMATCH[1]}"; elif [[ "$val" =~ ^\'(.*)\'$ ]]; then val="${BASH_REMATCH[1]}"; fi
      case "$key" in
        BACKUP_ENABLED|BACKUP_TARGET_DIR|BACKUP_PATHS|BACKUP_RETENTION_COUNT)
          printf -v "$key" '%s' "$val"
          ;;
      esac
    fi
  done < "$conf"
}

list_backups() {
  mkdir -p "$BACKUP_TARGET_DIR" 2>/dev/null || true
  ls -1t "${BACKUP_TARGET_DIR}"/spectre-docker-*-*.tar.gz 2>/dev/null || true
}

run_backup() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    err "Backup must run as root."
    exit 1
  fi

  BACKUP_ENABLED="${BACKUP_ENABLED,,}"
  if [[ "$BACKUP_ENABLED" != "yes" ]]; then
    log "Backups disabled (BACKUP_ENABLED=${BACKUP_ENABLED}); exiting."
    exit 0
  fi

  [[ "$BACKUP_RETENTION_COUNT" =~ ^[0-9]+$ ]] || { err "Invalid BACKUP_RETENTION_COUNT"; exit 1; }

  mkdir -p "$BACKUP_TARGET_DIR"
  chmod 750 "$BACKUP_TARGET_DIR" || true
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

  # Prevent concurrent runs
  exec 9>"${BACKUP_TARGET_DIR}/.spectre-docker-backup.lock"
  if command -v flock >/dev/null 2>&1; then
    flock -n 9 || { err "Another backup run is in progress; exiting."; exit 1; }
  fi

  local ts host archive p existing=()
  ts="$(date +%Y%m%d-%H%M%S)"
  host="$(hostname -s 2>/dev/null || echo host)"
  archive="${BACKUP_TARGET_DIR}/spectre-docker-${host}-${ts}.tar.gz"

  for p in ${BACKUP_PATHS}; do
    [[ -z "$p" ]] && continue
    if [[ -e "$p" ]]; then
      existing+=("$p")
    else
      log "Skipping missing path: $p"
    fi
  done

  if (( ${#existing[@]} == 0 )); then
    err "No existing paths to back up (BACKUP_PATHS='${BACKUP_PATHS}')."
    exit 1
  fi

  log "Starting backup: target='${archive}' paths='${existing[*]}'"
  tar -czpf "$archive" -- "${existing[@]}"
  chmod 640 "$archive" || true
  log "Backup created successfully: $archive ($(du -h "$archive" 2>/dev/null | awk '{print $1}' || echo '?'))"

  # Prune old archives matching our naming pattern
  local count=0
  # shellcheck disable=SC2012
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    count=$((count+1))
    if (( count > BACKUP_RETENTION_COUNT )); then
      if rm -f -- "$f"; then
        log "Pruned old backup: $f"
      else
        err "Failed to prune: $f"
      fi
    fi
  done < <(ls -1t "${BACKUP_TARGET_DIR}"/spectre-docker-*-*.tar.gz 2>/dev/null || true)

  log "Backup complete (retention=${BACKUP_RETENTION_COUNT})."
}

main() {
  local mode="backup"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage; exit 0 ;;
      --list) mode="list" ;;
      --config)
        shift; [[ $# -gt 0 ]] || { err "--config requires a path"; exit 1; }
        CONFIG_FILE="$1" ;;
      --config=*) CONFIG_FILE="${1#*=}" ;;
      *) err "Unknown argument: $1"; usage; exit 1 ;;
    esac
    shift
  done

  load_conf "$CONFIG_FILE"
  if [[ "$mode" == "list" ]]; then
    list_backups
    exit 0
  fi
  run_backup
}

main "$@"
