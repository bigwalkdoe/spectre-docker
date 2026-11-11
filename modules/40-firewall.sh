#!/usr/bin/env bash
# shellcheck shell=bash

_spectre_default_iface() {
  ip route show default 2>/dev/null | awk '/default/ {print $5; exit}' || true
}

run_module() {
  log_info "Configuring UFW firewall and Docker exposure safeguards..."
  ensure_packages ufw iproute2 iptables

  # Defaults
  ufw --force default deny incoming >/dev/null
  ufw --force default allow outgoing >/dev/null

  # Ensure SSH allowed (rate-limited) before enabling
  ufw limit "${SSH_PORT}/tcp" comment 'spectre-docker SSH' >/dev/null 2>&1 || ufw limit "${SSH_PORT}/tcp" >/dev/null

  # Extra ports
  local p
  for p in ${UFW_ALLOWED_TCP_PORTS}; do
    [[ -z "$p" ]] && continue
    if [[ "$p" =~ ^[0-9]+$ ]]; then
      ufw allow "${p}/tcp" comment 'spectre-docker extra' >/dev/null 2>&1 || ufw allow "${p}/tcp" >/dev/null
    else
      log_warn "Skipping invalid UFW_ALLOWED_TCP_PORTS entry: $p"
    fi
  done

  # Docker forward policy hardening in UFW defaults if present
  if [[ -f /etc/default/ufw ]]; then
    if grep -q '^DEFAULT_FORWARD_POLICY=' /etc/default/ufw; then
      sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="DROP"/' /etc/default/ufw
    else
      echo 'DEFAULT_FORWARD_POLICY="DROP"' >> /etc/default/ufw
    fi
  fi

  # Enable firewall (non-interactive)
  ufw --force enable >/dev/null
  log_ok "UFW enabled (default deny incoming, allow outgoing, SSH ${SSH_PORT}/tcp rate-limited)."

  # Install persistent Docker firewall helper and reapply hook
  local helper_src="${SCRIPT_DIR}/templates/firewall/spectre-docker-apply-docker-fw.sh"
  local dropin_src="${SCRIPT_DIR}/templates/firewall/spectre-docker-ufw.conf.tmpl"
  if [[ -f "$helper_src" ]]; then
    install -m 0750 -o root -g root "$helper_src" /usr/local/sbin/spectre-docker-apply-docker-fw
    log_info "Installed /usr/local/sbin/spectre-docker-apply-docker-fw"
  else
    log_warn "Missing firewall helper template: $helper_src"
  fi

  mkdir -p /etc/systemd/system/docker.service.d
  if [[ -f "$dropin_src" ]]; then
    if write_file_if_changed "/etc/systemd/system/docker.service.d/spectre-docker.conf" 0644 "root:root" "$dropin_src"; then
      systemctl daemon-reload || true
      log_info "Installed docker.service drop-in to reapply firewall restrictions after Docker starts."
    else
      log_info "docker.service firewall drop-in already up to date."
    fi
  fi

  # Apply now if Docker/chain is present (best-effort)
  if [[ -x /usr/local/sbin/spectre-docker-apply-docker-fw ]]; then
    /usr/local/sbin/spectre-docker-apply-docker-fw || true
    log_info "Applied conservative Docker forwarding restrictions where possible."
  fi

  ufw status verbose || true
}
