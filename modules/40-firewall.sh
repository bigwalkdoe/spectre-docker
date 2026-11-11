#!/usr/bin/env bash
# shellcheck shell=bash

_spectre_default_iface() {
  ip route show default 2>/dev/null | awk '/default/ {print $5; exit}' || true
}

_spectre_ensure_docker_user_rules() {
  # Conservative: prevent Docker published ports from being unintentionally exposed.
  # Allow established/related and traffic originating from docker bridges; drop NEW
  # forwarded traffic arriving on the default external interface. Intentional container
  # exposure should be managed explicitly (e.g. adjust DOCKER-USER rules or do not publish).
  command_exists iptables || return 0
  iptables -nL DOCKER-USER >/dev/null 2>&1 || return 0

  local ext_if
  ext_if="$(_spectre_default_iface)"

  # Ensure base accepts
  iptables -C DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    iptables -I DOCKER-USER 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -C DOCKER-USER -i lo -j ACCEPT 2>/dev/null || \
    iptables -I DOCKER-USER 2 -i lo -j ACCEPT
  iptables -C DOCKER-USER -i docker0 -j ACCEPT 2>/dev/null || true
  # br- interfaces (compose networks) - best effort accept from bridge side
  # (we avoid complex dynamic enumeration; Docker will manage its own rules, we only guard external ingress)

  if [[ -n "$ext_if" ]]; then
    # Drop NEW inbound forwarded traffic from external interface by default (placed at end if not present)
    if ! iptables -C DOCKER-USER -i "$ext_if" -m conntrack --ctstate NEW -j DROP 2>/dev/null; then
      iptables -A DOCKER-USER -i "$ext_if" -m conntrack --ctstate NEW -j DROP || true
    fi
  fi
}

run_module() {
  log_info "Configuring UFW firewall..."
  ensure_packages ufw iproute2

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

  # Apply Docker exposure mitigation (best-effort; DOCKER-USER may be (re)created by Docker later)
  _spectre_ensure_docker_user_rules || true
  log_info "Applied conservative Docker forwarding restrictions (DOCKER-USER) where possible."

  ufw status verbose || true
}
