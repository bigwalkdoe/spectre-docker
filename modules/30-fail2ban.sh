#!/usr/bin/env bash
# shellcheck shell=bash

run_module() {
  log_info "Installing and configuring fail2ban for SSH..."
  ensure_packages fail2ban

  local tmpl="${SCRIPT_DIR}/templates/fail2ban/jail.d/spectre-docker.local.tmpl"
  [[ -f "$tmpl" ]] || die "Missing fail2ban template: $tmpl"

  local tmp
  tmp="$(mktemp)"
  sed -e "s/__SSH_PORT__/${SSH_PORT}/g" "$tmpl" > "$tmp"

  local dest="/etc/fail2ban/jail.d/spectre-docker.local"
  local changed=0
  if write_file_if_changed "$dest" 0644 "root:root" "$tmp"; then
    changed=1
    log_info "Updated fail2ban jail: $dest"
  else
    log_info "Fail2ban jail already up to date: $dest"
  fi
  rm -f "$tmp"

  systemctl enable fail2ban >/dev/null 2>&1 || true
  if [[ $changed -eq 1 ]]; then
    systemctl restart fail2ban
  else
    systemctl is-active --quiet fail2ban || systemctl start fail2ban
  fi
  log_ok "fail2ban configured and running."
}
