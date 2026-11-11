#!/usr/bin/env bash
# shellcheck shell=bash

run_module() {
  log_info "Applying SSH hardening configuration..."
  ensure_packages openssh-server

  # Re-validate lockout safety with current system state (after users module)
  check_lockout_safety

  local tmpl="${SCRIPT_DIR}/templates/sshd/99-spectre-docker.conf.tmpl"
  [[ -f "$tmpl" ]] || die "Missing SSH template: $tmpl"

  local tmp
  tmp="$(mktemp)"
  sed \
    -e "s/__SSH_PORT__/${SSH_PORT}/g" \
    -e "s/__SSH_PERMIT_ROOT_LOGIN__/${SSH_PERMIT_ROOT_LOGIN}/g" \
    -e "s/__SSH_PASSWORD_AUTH__/${SSH_PASSWORD_AUTH}/g" \
    -e "s/__SSH_PUBKEY_AUTH__/${SSH_PUBKEY_AUTH}/g" \
    "$tmpl" > "$tmp"

  local dropin="/etc/ssh/sshd_config.d/99-spectre-docker.conf"
  mkdir -p /etc/ssh/sshd_config.d

  local changed=0
  if write_file_if_changed "$dropin" 0644 "root:root" "$tmp"; then
    changed=1
    log_info "Updated SSH drop-in: $dropin"
  else
    log_info "SSH drop-in already up to date: $dropin"
  fi
  rm -f "$tmp"

  # Validate before reload
  if ! sshd -t; then
    die "sshd configuration test failed (sshd -t). Aborting without reload."
  fi

  local svc
  svc="$(get_ssh_service_name)"
  if [[ $changed -eq 1 ]]; then
    log_info "Reloading SSH service (${svc})..."
    systemctl reload "$svc" 2>/dev/null || systemctl restart "$svc"
    log_ok "SSH configuration applied and service reloaded."
  else
    # Ensure service is enabled/running even if config unchanged
    systemctl enable "$svc" >/dev/null 2>&1 || true
    systemctl is-active --quiet "$svc" || systemctl start "$svc" || true
    log_ok "SSH configuration unchanged; service ensured active."
  fi
}
