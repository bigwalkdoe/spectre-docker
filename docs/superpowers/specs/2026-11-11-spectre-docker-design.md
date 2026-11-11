# spectre-docker — Design

**Date:** 2026-11-11  
**Status:** Draft (pending approval)

## Intent and why

Turn this repository into **spectre-docker**: an automated, opinionated bootstrap for a **fresh Ubuntu or Debian server** (e.g. a DigitalOcean droplet). A user clones the repo onto a new machine, edits a single config file, and runs the setup to obtain a hardened Docker host with a solid baseline—so they can deploy their own applications, databases, and software themselves without manual server provisioning.

This repo currently contains `spectre-server-layer`, a Docker Compose application stack (nginx, Node app, PostgreSQL, Redis). That stack is **removed/replaced**; `spectre-docker` is purely the host bootstrap (install and harden Docker plus baseline). Kubernetes is out of scope for this project and will be handled by a separate `spectre-k8s` project.

## Goals

- Provide a “clone → configure → run” bootstrap for fresh **Ubuntu** and **Debian** servers.
- Install and harden **Docker Engine + Compose plugin** and enable it on boot.
- Apply an opinionated baseline: non-root admin user, SSH hardening, firewall, permissions, baseline configs, automatic security updates, intrusion protection for SSH, and scheduled backups.
- Be **idempotent** and **re-runnable**: modules detect current state and converge safely.
- Be transparent and auditable: modular Bash scripts, minimal prerequisites, config-driven.
- Leave application deployment/running entirely to the user (no app runner/orchestration of user workloads).

## Non-goals

- Managing, deploying, or running user applications/containers (no PaaS/runner behavior).
- Kubernetes installation or configuration (separate `spectre-k8s` project).
- Supporting non-Debian-based distributions (RHEL/Fedora/Arch/etc.) in this design.
- Providing a web UI or remote control plane.
- Multi-node/cluster orchestration.
- Cloud-provider-specific provisioning APIs (it runs *on* the server; creating the droplet is out of scope).

## Anti-goals (would make this a failure even if it “works”)

- Requiring manual, undocumented steps to reach a usable hardened state after running setup.
- Silently weakening security (e.g. leaving password/root SSH enabled without explicit opt-in, or exposing container ports unintentionally).
- Destructive, non-idempotent behavior that breaks a server on re-run or clobbers user data/config without clear intent.
- Pretending to back up arbitrary application data it doesn’t know about; backups must be explicit and documented.
- Retaining the old `spectre-server-layer` application-stack identity or sample workload in a confusing/partial way.

## Constraints

- **Target OS:** Ubuntu and Debian (current/LTS releases commonly used on fresh servers). Scripts must detect the distro and use `apt`-based flows; fail clearly on unsupported systems.
- **Privileges:** setup requires root (or sudo). It must check and exit with a clear message if not privileged.
- **Network:** needs outbound access to install packages (Docker official repo, distro packages). Must function on a typical fresh droplet with default networking.
- **No secrets committed:** real config (which may contain paths/choices; SSH keys are public material but treat config as local) must not be committed. Provide an example config.
- **Existing repo state:** current tree contains the Compose stack (`app/`, `configs/docker-compose.yml`, `configs/nginx/`, `volumes/`, stack scripts). These are removed as part of the transformation; git history remains.
- **Docker + firewall:** Docker manipulates iptables/nftables and can bypass naive UFW rules for published ports. The design must address this explicitly.

## Approaches (considered)

1. **Modular idempotent Bash scripts (chosen).** `setup.sh` entrypoint sourcing small, single-purpose modules (e.g. `modules/preflight.sh`, `modules/users.sh`, `modules/ssh.sh`, `modules/firewall.sh`, `modules/docker.sh`, `modules/updates.sh`, `modules/backups.sh`). Each converges state and is safe to re-run. *Trade-off:* minimal dependencies and easy to audit on a fresh box (fits “clone & run”), but correctness/idempotency discipline is our responsibility. Best match for a transparent single-node bootstrap.
2. **Ansible playbook/roles.** Declarative and strongly idempotent, good for fleets. *Trade-off:* requires Ansible dependency and more structure; heavier than needed for a one-shot/occasional single-host bootstrap.
3. **Cloud-init / image-oriented bootstrap.** Hands-off for droplet user-data/images. *Trade-off:* less repo-centric and harder to iterate locally; platform-coupled.

**Chosen:** (1) Modular idempotent Bash scripts.

## Decided parts (how it works)

### Repository layout (post-transformation)

Remove/replace the application stack and its artifacts: `app/`, `volumes/`, `configs/docker-compose.yml`, `configs/.env.example`, `configs/nginx/`, `gen-dev-cert.sh`, `start.sh`, `stop.sh`, `status.sh`, `logs.sh`, `smoke-test.sh` (and any other stack-only files). Replace with:

- `setup.sh` — main entrypoint (root). Parses/loads config, runs modules in order, prints a summary.
- `uninstall.sh` or `teardown` helpers **not** required; document manual reversal where appropriate (destructive automation is out of scope) — but modules must be non-destructive on re-run.
- `config/spectre-docker.conf.example` — documented example config; real `config/spectre-docker.conf` is gitignored.
- `config/.gitignore` — ignore real config/state as needed.
- `modules/` — idempotent modules, e.g. `00-preflight.sh`, `10-users.sh`, `20-ssh.sh`, `30-firewall.sh`, `40-docker.sh`, `50-updates.sh`, `60-fail2ban.sh`, `70-backups.sh` (exact naming/ordering settled at implementation, but single-responsibility and ordered).
- `lib/common.sh` — shared helpers (logging, distro detection, `ensure_line_in_file`, package install helpers, idempotent checks, config loading/validation).
- `templates/` — config templates/snippets as needed (e.g. sshd hardening drop-in, fail2ban jail, Docker daemon.json, backup script/timer units).
- `docs/` — usage/operations notes as useful (kept concise; README is primary).
- Updated `README.md`, `LICENSE` (retained), `CONTRIBUTING.md`, `SECURITY.md`, `AGENTS.md`, `CHANGELOG.md` aligned to `spectre-docker`. Remove/retire `.githooks`/workflows only if irrelevant; otherwise update to match new project.

All naming/references consistently use `spectre-docker` (no `spectre-server-layer` branding in user-facing materials, except historical changelog context if preserved).

### Configuration (`config/spectre-docker.conf`)

A shell-sourceable or simple `KEY=VALUE` config file (documented format; parsed safely—no execution of untrusted content beyond defined variables). Example keys (with sensible defaults where safe):

- `ADMIN_USER` (default: `deploy`) — non-root admin user to create/ensure.
- `ADMIN_SSH_PUBLIC_KEYS` — path to a file containing public key(s) or inline key(s) as supported; required to guarantee access when password auth is disabled (setup must warn/fail safely if it would lock out access—see SSH).
- `SSH_PORT` (default: `22`).
- `SSH_PASSWORD_AUTH` (default: `no`).
- `SSH_PERMIT_ROOT_LOGIN` (default: `no`).
- `SSH_PUBKEY_AUTH` (default: `yes`).
- `UFW_ALLOWED_TCP_PORTS` (default: empty beyond SSH) — extra ports to allow.
- `BACKUP_ENABLED` (default: `yes`).
- `BACKUP_TARGET_DIR` (default: `/var/backups/spectre-docker`).
- `BACKUP_PATHS` — additional paths to include (default includes `/etc` and spectre-docker config/state paths such as `/etc/spectre-docker` or the repo config copy; exact set documented).
- `BACKUP_RETENTION_COUNT` (default: `7`).
- `BACKUP_SCHEDULE` (default: daily, e.g. via cron or systemd timer) — sensible default, configurable.

Defaults are opinionated and secure; anything risky (e.g. enabling password auth) is explicit opt-in.

### Baseline behavior (opinionated defaults)

- **Preflight:** verify root, supported OS (Ubuntu/Debian) via `/etc/os-release`, `apt` available, basic connectivity assumptions surfaced; set sane shell options (`set -euo pipefail`) in scripts.
- **Users/auth/permissions:** ensure `ADMIN_USER` exists with a home dir; add to `sudo` (and `docker` later) groups; set secure permissions on home and `.ssh` (`700`/`600`); install authorized keys idempotently. Do not create passwordless sudo by default.
- **SSH:** manage hardening via a drop-in (e.g. `/etc/ssh/sshd_config.d/99-spectre-docker.conf`) to avoid clobbering distro defaults; set `PermitRootLogin no`, `PasswordAuthentication no` (default), `PubkeyAuthentication yes`, `MaxAuthTries` limited, `PermitEmptyPasswords no`, and keep `Port` configurable. **Lockout safety:** if disabling password auth and no authorized key would be present for a viable admin path, fail with a clear error (or require explicit override) rather than applying a lockout. Validate config (`sshd -t`) before reload; reload/restart ssh service appropriately (`ssh`/`sshd` name varies by distro).
- **Fail2ban:** install and enable `fail2ban` with a jail protecting SSH (using configured port); default banaction aligned with UFW/nftables as appropriate for Ubuntu/Debian.
- **Firewall/network:** install/enable UFW, default deny incoming / allow outgoing; allow `SSH_PORT` (rate-limited, e.g. `ufw limit`); allow configured extra TCP ports. Enable UFW only after rules ensure SSH access. **Docker exposure:** address Docker bypassing UFW by configuring forwarding/DOCKER-USER restrictions or integrating a standard, documented approach (e.g. UFW `DEFAULT_FORWARD_POLICY`/after.rules and/or a `DOCKER-USER` chain that defaults to drop for external interfaces while allowing established traffic and explicit publishes) so container ports are not unintentionally world-open; document the behavior and limitations clearly.
- **Updates/time:** install/enable `unattended-upgrades` for security updates (distro-standard config) and ensure time synchronization is active (`systemd-timesyncd` or chrony as available/default) — prefer the distro default already present.
- **Docker:** install prerequisites, add Docker’s official apt repository and GPG key for the detected distro/codename/arch, install `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`; enable and start `docker`. Add `ADMIN_USER` to `docker` group. Configure `/etc/docker/daemon.json` with safe defaults (e.g. `log-driver` json-file with `max-size`/`max-file` rotation like `10m`/`3`, and `live-restore` considered) idempotently, merging/replacing in a controlled, documented way; restart Docker only when config changes.
- **Backups:** dependency-light default: a root-run backup script (installed to a known path, e.g. `/usr/local/sbin/spectre-docker-backup`) scheduled daily (cron or systemd timer—implementation chooses one consistently) that creates compressed archives (e.g. `tar.gz`) of configured paths into `BACKUP_TARGET_DIR`, with timestamped names and retention pruning to `BACKUP_RETENTION_COUNT`. Backs up host/config state and explicitly configured paths (default includes `/etc` and spectre-docker managed config/state location); **does not** guess application data beyond configured paths. Logs outcome; provides/ documents a restore procedure (extract relevant paths). Remote targets are out of scope by default but `BACKUP_TARGET_DIR` can point to a mounted path.

### UX & operations

- `sudo ./setup.sh` (or equivalent) after copying/editing config: clear preflight errors, step-by-step logging, final summary of actions and any manual follow-ups (e.g. re-login for docker group, confirm SSH key access).
- `--help`/usage output; optional `--check/--dry-run` is nice-to-have (left to builder if low-cost) but not required.
- Re-runs converge without duplicating config entries or breaking services.

## What’s left to the builder

- Exact module breakdown/order and function-level structure within the stated responsibilities.
- Choice of cron vs systemd timer for backups (pick one, implement consistently, document).
- Precise, correct implementation of Docker-vs-UFW/iptables handling for supported Ubuntu/Debian versions (may differ between nftables/iptables backends) while honoring the stated intent: do not unintentionally expose published ports.
- Exact `daemon.json` keys, sshd hardening parameters beyond the stated minimums, and fail2ban jail specifics, so long as they meet the defaults/intent above.
- Safe config parsing/validation details and exact lockout-prevention checks.
- Which stack-specific repo files beyond those listed (e.g. CI workflows, issue templates, devcontainer/devin artifacts) to delete, keep, or rewrite to fit `spectre-docker`.
- Exact default `BACKUP_PATHS` set and whether to copy repo config into `/etc/spectre-docker` as managed state (recommended for clarity) — must be documented.
- README/operations docs content and CHANGELOG rewrite strategy (preserve history vs reset) consistent with the rename.
- Testing/verification approach appropriate for shell bootstrap (e.g. shellcheck, bats/shunit2, or manual verification steps) given environment constraints.

## Approvals & next step

Design requires explicit human approval before implementation. After approval: invoke **writing-plans** to produce the implementation plan (no other implementation skill).
