#!/usr/bin/env bash
# shellcheck shell=bash

run_module() {
  log_info "Configuring automatic security updates and time synchronization..."
  ensure_packages unattended-upgrades ca-certificates

  # Enable unattended upgrades non-interactively (distro-standard mechanism)
  if command_exists dpkg-reconfigure; then
    echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | debconf-set-selections 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true
  fi
  systemctl enable unattended-upgrades >/dev/null 2>&1 || true
  systemctl start unattended-upgrades >/dev/null 2>&1 || systemctl restart unattended-upgrades >/dev/null 2>&1 || true

  # Time sync: prefer systemd-timesyncd if available
  if systemctl list-unit-files --type=service 2>/dev/null | grep -q '^systemd-timesyncd\.service'; then
    systemctl enable systemd-timesyncd >/dev/null 2>&1 || true
    systemctl start systemd-timesyncd >/dev/null 2>&1 || true
    timedatectl set-ntp true >/dev/null 2>&1 || true
    log_ok "Time synchronization ensured (systemd-timesyncd)."
  elif systemctl list-unit-files --type=service 2>/dev/null | grep -q '^chrony\.service'; then
    systemctl enable chrony >/dev/null 2>&1 || true
    systemctl start chrony >/dev/null 2>&1 || true
    log_ok "Time synchronization ensured (chrony)."
  else
    log_warn "No known time sync service found; ensure NTP is configured."
  fi

  log_ok "Unattended upgrades configured."
}
