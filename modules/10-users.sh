#!/usr/bin/env bash
# shellcheck shell=bash

_spectre_collect_admin_keys() {
  local src="$ADMIN_SSH_PUBLIC_KEYS"
  [[ -n "$src" ]] || return 0
  if [[ -f "$src" ]]; then
    cat "$src"
  else
    printf '%s\n' "$src"
  fi
}

run_module() {
  log_info "Ensuring admin user '${ADMIN_USER}' exists with secure SSH/sudo setup..."
  if ! id "$ADMIN_USER" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "$ADMIN_USER"
    log_ok "Created user '${ADMIN_USER}'."
  else
    log_info "User '${ADMIN_USER}' already exists."
  fi

  # Ensure sudo group membership
  if getent group sudo >/dev/null 2>&1; then
    usermod -aG sudo "$ADMIN_USER"
  elif getent group wheel >/dev/null 2>&1; then
    usermod -aG wheel "$ADMIN_USER"
  else
    log_warn "No sudo/wheel group found; cannot grant sudo membership automatically."
  fi

  local home_dir
  home_dir="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"
  [[ -n "$home_dir" && -d "$home_dir" ]] || die "Could not determine home directory for '${ADMIN_USER}'."

  mkdir -p "$home_dir/.ssh"
  chmod 700 "$home_dir/.ssh"
  chown "$ADMIN_USER":"$ADMIN_USER" "$home_dir/.ssh"

  local auth_keys="$home_dir/.ssh/authorized_keys"
  touch "$auth_keys"
  chmod 600 "$auth_keys"
  chown "$ADMIN_USER":"$ADMIN_USER" "$auth_keys"

  # Install authorized keys idempotently
  local keys_tmp added=0
  keys_tmp="$(mktemp)"
  _spectre_collect_admin_keys | sed '/^[[:space:]]*$/d' > "$keys_tmp" || true
  if [[ -s "$keys_tmp" ]]; then
    while IFS= read -r keyline || [[ -n "$keyline" ]]; do
      [[ -z "${keyline//[[:space:]]/}" ]] && continue
      if ! grep -qxF "$keyline" "$auth_keys"; then
        echo "$keyline" >> "$auth_keys"
        added=$((added+1))
      fi
    done < "$keys_tmp"
    log_ok "Authorized keys ensured for '${ADMIN_USER}' (${added} new)."
  else
    log_warn "No ADMIN_SSH_PUBLIC_KEYS provided; leaving existing authorized_keys unchanged."
  fi
  rm -f "$keys_tmp"

  # Ensure home ownership is sane (without being overly destructive)
  chown "$ADMIN_USER":"$ADMIN_USER" "$home_dir" || true
}
