#!/usr/bin/env bash
set -euo pipefail

# Managed by spectre-docker
# Reapplies conservative DOCKER-USER restrictions so Docker-published ports are not
# unintentionally exposed on the external interface. Best-effort across restarts.

default_iface() {
  ip route show default 2>/dev/null | awk '/default/ {print $5; exit}' || true
}

apply_iptables() {
  local bin="$1"
  local ext_if="$2"
  command -v "$bin" >/dev/null 2>&1 || return 0
  "$bin" -nL DOCKER-USER >/dev/null 2>&1 || return 0

  # Ensure base accepts at top (idempotent)
  "$bin" -C DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    "$bin" -I DOCKER-USER 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT || true
  "$bin" -C DOCKER-USER -i lo -j ACCEPT 2>/dev/null || \
    "$bin" -I DOCKER-USER 2 -i lo -j ACCEPT || true
  "$bin" -C DOCKER-USER -i docker0 -j RETURN 2>/dev/null || \
    "$bin" -I DOCKER-USER 3 -i docker0 -j RETURN 2>/dev/null || true

  if [[ -n "$ext_if" ]]; then
    if ! "$bin" -C DOCKER-USER -i "$ext_if" -m conntrack --ctstate NEW -j DROP 2>/dev/null; then
      "$bin" -A DOCKER-USER -i "$ext_if" -m conntrack --ctstate NEW -j DROP || true
    fi
  fi

  # Return at end to allow Docker-managed rules/decisions for other cases
  if ! "$bin" -C DOCKER-USER -j RETURN 2>/dev/null; then
    "$bin" -A DOCKER-USER -j RETURN 2>/dev/null || true
  fi
}

main() {
  local ext_if
  ext_if="$(default_iface)"
  # Wait briefly for DOCKER-USER to exist if Docker is starting
  local i
  for i in 1 2 3 4 5; do
    if iptables -nL DOCKER-USER >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  apply_iptables iptables "$ext_if"
  # IPv6 best-effort (if DOCKER-USER exists in ip6tables)
  apply_iptables ip6tables "$ext_if"
}

main "$@"
