#!/usr/bin/env bash
# shellcheck shell=bash

run_module() {
  log_info "Checking privileges and operating system..."
  require_root
  assert_supported_os
  command_exists systemctl || die "systemctl is required (systemd-based Ubuntu/Debian expected)."
  apt_update_once
  log_ok "Preflight checks passed (${SPECTRE_OS_ID} ${SPECTRE_OS_VERSION_ID})."
}
