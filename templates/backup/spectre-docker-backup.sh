#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/spectre-docker/spectre-docker.conf"
BACKUP_ENABLED="yes"
BACKUP_TARGET_DIR="/var/backups/spectre-docker"
BACKUP_PATHS="/etc /etc/spectre-docker"
BACKUP_RETENTION_COUNT="7"

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
err() { printf '[%s] ERROR: %s\n' "$(date -Is)" "$*" >&2; }

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

main() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    err "Backup must run as root."
    exit 1
  fi

  load_conf "$CONFIG_FILE"
  BACKUP_ENABLED="${BACKUP_ENABLED,,}"

  if [[ "$BACKUP_ENABLED" != "yes" ]]; then
    log "Backups disabled (BACKUP_ENABLED=${BACKUP_ENABLED}); exiting."
    exit 0
  fi

  [[ "$BACKUP_RETENTION_COUNT" =~ ^[0-9]+$ ]] || { err "Invalid BACKUP_RETENTION_COUNT"; exit 1; }

  mkdir -p "$BACKUP_TARGET_DIR"
  chmod 750 "$BACKUP_TARGET_DIR" || true

  local ts host archive tmp_list=() p existing=()
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

  log "Creating backup archive: $archive"
  # Create archive with absolute paths preserved for straightforward restore
  tar -czpf "$archive" -- "${existing[@]}"
  chmod 640 "$archive" || true
  log "Backup created successfully: $archive"

  # Prune old archives matching our naming pattern
  local count=0
  # shellcheck disable=SC2012
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    count=$((count+1))
    if (( count > BACKUP_RETENTION_COUNT )); then
      rm -f -- "$f" && log "Pruned old backup: $f" || err "Failed to prune: $f"
    fi
  done < <(ls -1t "${BACKUP_TARGET_DIR}"/spectre-docker-*-*.tar.gz 2>/dev/null || true)

  log "Backup complete."
}

main "$@"
