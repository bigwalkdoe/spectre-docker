#!/usr/bin/env bash
# shellcheck shell=bash

run_module() {
  log_info "Installing and configuring Docker Engine and Compose plugin..."
  detect_os

  # Remove conflicting packages (ignore if absent)
  local conflicts=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)
  local c to_remove=()
  for c in "${conflicts[@]}"; do
    if dpkg -s "$c" >/dev/null 2>&1; then
      to_remove+=("$c")
    fi
  done
  if (( ${#to_remove[@]} > 0 )); then
    log_info "Removing conflicting packages: ${to_remove[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get remove -y "${to_remove[@]}" >/dev/null 2>&1 || true
  fi

  ensure_packages ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  local gpg_url=""
  case "$SPECTRE_OS_ID" in
    ubuntu) gpg_url="https://download.docker.com/linux/ubuntu/gpg" ;;
    debian) gpg_url="https://download.docker.com/linux/debian/gpg" ;;
    *)      gpg_url="https://download.docker.com/linux/${SPECTRE_OS_ID}/gpg" ;;
  esac

  local keyring="/etc/apt/keyrings/docker.asc"
  if [[ ! -f "$keyring" ]]; then
    curl -fsSL "$gpg_url" -o "$keyring"
    chmod a+r "$keyring"
    log_info "Installed Docker GPG key."
  else
    log_info "Docker GPG key already present."
  fi

  local arch codename
  arch="$(dpkg --print-architecture)"
  codename="${SPECTRE_OS_CODENAME}"
  if [[ -z "$codename" && -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    codename="${VERSION_CODENAME:-}"
  fi
  [[ -n "$codename" ]] || die "Unable to determine OS codename for Docker apt repo."

  local repo_file="/etc/apt/sources.list.d/docker.list"
  local repo_line="deb [arch=${arch} signed-by=${keyring}] https://download.docker.com/linux/${SPECTRE_OS_ID} ${codename} stable"
  local tmprepo
  tmprepo="$(mktemp)"
  printf '%s\n' "$repo_line" > "$tmprepo"
  if write_file_if_changed "$repo_file" 0644 "root:root" "$tmprepo"; then
    log_info "Configured Docker apt repository."
    _SPECTRE_APT_UPDATED=""
  else
    log_info "Docker apt repository already configured."
  fi
  rm -f "$tmprepo"

  apt_update_once
  ensure_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable docker >/dev/null 2>&1 || true
  systemctl start docker >/dev/null 2>&1 || systemctl restart docker >/dev/null 2>&1 || true
  systemctl enable containerd >/dev/null 2>&1 || true
  systemctl start containerd >/dev/null 2>&1 || true

  # Add admin user to docker group
  if id "$ADMIN_USER" >/dev/null 2>&1; then
    if ! id -nG "$ADMIN_USER" | grep -qw docker; then
      usermod -aG docker "$ADMIN_USER"
      log_ok "Added '${ADMIN_USER}' to docker group."
    else
      log_info "User '${ADMIN_USER}' already in docker group."
    fi
  else
    log_warn "Admin user '${ADMIN_USER}' not found; skipping docker group membership."
  fi

  # Daemon configuration
  local daemon_src="${SCRIPT_DIR}/templates/docker/daemon.json"
  [[ -f "$daemon_src" ]] || die "Missing Docker daemon template: $daemon_src"
  mkdir -p /etc/docker
  local changed=0
  if write_file_if_changed "/etc/docker/daemon.json" 0644 "root:root" "$daemon_src"; then
    changed=1
    log_info "Updated /etc/docker/daemon.json"
  else
    log_info "Docker daemon.json already up to date."
  fi

  if [[ $changed -eq 1 ]]; then
    log_info "Restarting Docker to apply daemon configuration..."
    systemctl restart docker
  fi

  log_ok "Docker Engine and Compose plugin installed and configured."
}
