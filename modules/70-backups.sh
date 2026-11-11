#!/usr/bin/env bash
# shellcheck shell=bash

_spectre_cron_schedule() {
  case "${BACKUP_SCHEDULE}" in
    daily)  echo "30 2 * * *" ;;
    hourly) echo "30 * * * *" ;;
    *)
      # accept 5-field cron expression
      if [[ "${BACKUP_SCHEDULE}" =~ ^([^\ ]+[[:space:]]+){4}[^\ ]+$ ]]; then
        echo "${BACKUP_SCHEDULE}"
      else
        log_warn "Unrecognized BACKUP_SCHEDULE '${BACKUP_SCHEDULE}', defaulting to daily."
        echo "30 2 * * *"
      fi
      ;;
  esac
}

run_module() {
  log_info "Configuring backup script and schedule..."
  ensure_packages cron tar gzip

  mkdir -p "$BACKUP_TARGET_DIR"
  chmod 750 "$BACKUP_TARGET_DIR" || true
  mkdir -p /etc/spectre-docker
  chmod 755 /etc/spectre-docker

  local bsrc="${SCRIPT_DIR}/templates/backup/spectre-docker-backup.sh"
  [[ -f "$bsrc" ]] || die "Missing backup script template: $bsrc"
  install -m 0750 -o root -g root "$bsrc" /usr/local/sbin/spectre-docker-backup
  log_ok "Installed /usr/local/sbin/spectre-docker-backup"

  local cron_dest="/etc/cron.d/spectre-docker-backup"
  if [[ "$BACKUP_ENABLED" == "yes" ]]; then
    local tmpl="${SCRIPT_DIR}/templates/backup/spectre-docker-backup.cron.tmpl"
    [[ -f "$tmpl" ]] || die "Missing cron template: $tmpl"
    local spec tmp
    spec="$(_spectre_cron_schedule)"
    tmp="$(mktemp)"
    sed -e "s/__CRON_SCHEDULE__/${spec}/g" "$tmpl" > "$tmp"
    if write_file_if_changed "$cron_dest" 0644 "root:root" "$tmp"; then
      log_info "Installed backup cron schedule (${spec})."
    else
      log_info "Backup cron schedule already up to date."
    fi
    rm -f "$tmp"
    systemctl enable cron >/dev/null 2>&1 || systemctl enable crond >/dev/null 2>&1 || true
    systemctl start cron >/dev/null 2>&1 || systemctl start crond >/dev/null 2>&1 || true
  else
    if [[ -f "$cron_dest" ]]; then
      rm -f "$cron_dest"
      log_info "BACKUP_ENABLED=no; removed backup cron schedule."
    else
      log_info "BACKUP_ENABLED=no; backup cron schedule not installed."
    fi
  fi

  log_ok "Backup module configured."
}
