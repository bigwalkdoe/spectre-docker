# spectre-docker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform this repository from `spectre-server-layer` into `spectre-docker`: a config-driven, modular, idempotent Bash bootstrap that hardens a fresh Ubuntu/Debian server and installs Docker (no app runner).

**Architecture:** A root-invoked `setup.sh` loads `config/spectre-docker.conf`, runs ordered single-responsibility modules under `modules/` using shared helpers in `lib/common.sh`, and converges system state (users, SSH, firewall, fail2ban, unattended upgrades, Docker, backups) idempotently. The existing Compose application stack is removed and replaced with bootstrap assets, templates, and updated docs/metadata.

**Tech Stack:** Bash (`set -euo pipefail`), core Linux/Ubuntu/Debian tooling (`apt-get`, `systemctl`, `sshd`, `ufw`, `fail2ban`, `cron`/systemd timer as chosen), Docker Engine official apt repo + Compose plugin, `tar`/`gzip` for backups, git.

**Spec:** `docs/superpowers/specs/2026-11-11-spectre-docker-design.md`

## Global Constraints

- **Target OS:** Ubuntu and Debian only (currently supported LTS/stable, e.g. Ubuntu 22.04/24.04+, Debian 12+). Detect via `/etc/os-release`; fail clearly on unsupported systems. Use `apt`-based flows.
- **Privileges:** Setup requires root (or sudo). Check and exit with a clear message if not privileged.
- **Idempotent & non-destructive:** Safe to re-run; converge state without duplicating config or clobbering user data/config without clear intent. Do not add destructive teardown automation.
- **Config-driven:** Real settings come from `config/spectre-docker.conf` (gitignored). Provide `config/spectre-docker.conf.example`. Parse safely (no execution of untrusted content).
- **Security defaults (opinionated, explicit opt-in to weaken):** non-root admin user with sudo; SSH root login off, pubkey auth on, password auth off by default; lockout safety (fail if disabling password auth with no viable admin key unless explicit override); UFW default deny incoming/allow outgoing, SSH rate-limited, only configured extra ports; Docker/iptables exposure handled intentionally (no inadvertent world-open published ports); unattended upgrades + time sync; fail2ban for SSH.
- **Docker:** install Docker Engine + Compose plugin from official repos, enabled on boot; deploy user in `docker` group; daemon defaults include log rotation.
- **Backups:** dependency-light scheduled backups of host/config state and explicitly configured paths only (no guessing app data) to configurable target, with retention and documented restore.
- **No secrets committed.** No `spectre-server-layer` branding/sample workload remains.

## Review Focus

1. **Lockout scenarios** (SSH password auth disabled but no admin public key configured/present, or bad SSH config applied): setup must fail safely or refuse to apply, and must validate (`sshd -t`) before reload — a person should never be locked out by a default run.
2. **Docker + firewall interaction on Ubuntu/Debian (iptables/nftables backends):** container published ports must not become unintentionally exposed to the world contrary to UFW intent; behavior/limits must be explicit.
3. **Idempotent re-runs:** re-running `setup.sh` must not duplicate `sshd` drop-ins/authorized_keys/cron or timer entries/UFW rules/apt repo config or break services — state should converge cleanly.
4. **Unsupported OS or missing privileges/network:** running on non-Ubuntu/Debian or without root, or when package installs fail, must exit with clear, actionable errors (no partial, silent half-configuration presented as success).
5. **Config parsing/validation safety:** malformed or missing `config/spectre-docker.conf`, unsafe values, or unset required-for-safety fields (e.g. admin user/keys relative to auth policy) must be rejected clearly without executing arbitrary content.

---

## File Structure

**Remove (stack-specific):** `app/` (all), `volumes/` (all), `configs/docker-compose.yml`, `configs/.env.example`, `configs/nginx/` (all), `configs/.gitignore` (replaced), `gen-dev-cert.sh`, `start.sh`, `stop.sh`, `status.sh`, `logs.sh`, `smoke-test.sh`.

**Create/replace (bootstrap):**
- `setup.sh` — executable entrypoint: preflight checks, load/validate config, run modules in order, summary.
- `lib/common.sh` — logging, colors (TTY-safe), die/require_root, OS detection (`is_supported_os`, `os_id`), command checks, apt helpers, idempotent file/line helpers, config load/validate helpers, service enable/reload helpers.
- `config/spectre-docker.conf.example` — fully documented example with defaults.
- `config/.gitignore` — ignores `spectre-docker.conf` and local state.
- `modules/00-preflight.sh` — root, OS, apt/network sanity.
- `modules/10-users.sh` — ensure admin user, sudo, ssh dir/perms, authorized keys.
- `modules/20-ssh.sh` — sshd hardening drop-in, lockout safety, validate & reload.
- `modules/30-fail2ban.sh` — install/configure fail2ban jail for SSH.
- `modules/40-firewall.sh` — UFW defaults, SSH rate limit, extra ports, Docker exposure handling.
- `modules/50-updates.sh` — unattended-upgrades, time sync.
- `modules/60-docker.sh` — official repo, packages, enable, group, daemon.json (log rotation).
- `modules/70-backups.sh` — backup script install, schedule (cron or systemd timer — pick one), retention logic; install/ensure paths.
- `templates/sshd/99-spectre-docker.conf.tmpl` (or rendered content) — sshd drop-in template/content.
- `templates/fail2ban/jail.d/spectre-docker.local.tmpl` — SSH jail.
- `templates/docker/daemon.json` — baseline daemon config.
- `templates/backup/spectre-docker-backup.sh` — backup script template/source.
- `templates/backup/spectre-docker-backup.cron` or systemd `*.service`/`*.timer` templates — schedule (one chosen).
- `README.md` — rewritten for spectre-docker (usage, config, security notes, backups/restore, Docker/UFW notes).
- `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `AGENTS.md` — updated to spectre-docker; remove stack-specific instructions.
- `.gitignore` — updated (remove stack-specific ignores as needed, add config/state/backup artifacts).
- `.github/workflows/*`, `.github/ISSUE_TEMPLATE/*`, `.github/pull_request_template.md`, `dependabot.yml` — updated or removed to match (no Node/app tests unless replaced with relevant checks like shellcheck/bash -n).

---

### Task 1: Remove the application stack and rename project identity

**Files:**
- Delete: `app/` (recursive), `volumes/` (recursive), `configs/docker-compose.yml`, `configs/.env.example`, `configs/nginx/` (recursive), `gen-dev-cert.sh`, `start.sh`, `stop.sh`, `status.sh`, `logs.sh`, `smoke-test.sh`
- Modify: `configs/.gitignore` (replace), `.gitignore` (update), `README.md` (temporary minimal placeholder to be fully rewritten in Task 9), `CHANGELOG.md`, `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`
- Modify: `.mailmap` (keep or adjust only if needed)

**Interfaces:**
- Produces: a clean repo with no `spectre-server-layer` runtime stack; bootstrap structure added in later tasks will be the only product.

- [ ] **Step 1: Inventory and remove stack-specific files/directories**

Run: `git rm -r app volumes configs/nginx && git rm configs/docker-compose.yml configs/.env.example gen-dev-cert.sh start.sh stop.sh status.sh logs.sh smoke-test.sh`
Expected: stack files removed from index/worktree.

- [ ] **Step 2: Replace `configs/.gitignore` and update root `.gitignore`**

Create/replace `configs/.gitignore` to ignore `spectre-docker.conf` and local runtime state. Update root `.gitignore` to remove obsolete stack entries and ignore any bootstrap runtime artifacts (e.g. local backup output paths if created in-repo for tests) while keeping cert/key-like secrets ignored if relevant.
Expected: `git status` shows intended ignore behavior.

- [ ] **Step 3: Sweep and replace user-facing `spectre-server-layer` identity**

Search: `rg -n "spectre-server-layer|spectre server layer" .` and replace with `spectre-docker` (or remove stack-specific meaning) in `README.md` (minimal placeholder noting bootstrap-in-progress), `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `AGENTS.md`. Preserve license/history intent where appropriate.
Expected: no stale project identity in user-facing docs except intentional historical notes if any.

- [ ] **Step 4: Verify no app stack remains**

Run: `find . -maxdepth 3 -type f | sort` and `rg -n "spectre-server-layer" . || true`
Expected: no `app/`, no compose/nginx stack, no (or only intentional historical) old name references.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove sample stack and rename project to spectre-docker"
```

### Task 2: Scaffold config, library, and entrypoint skeleton

**Files:**
- Create: `config/spectre-docker.conf.example`, `config/.gitignore` (if not finalized), `lib/common.sh`, `setup.sh`, `modules/.gitkeep` (optional), `templates/.gitkeep` (optional)

**Interfaces:**
- Produces: `setup.sh` (executable) that sources `lib/common.sh` and loads/validates config; `lib/common.sh` exports/defines logging (`log_info`, `log_warn`, `log_error`, `die`), `require_root`, `detect_os`/`assert_supported_os`, `load_config <path>` with safe parsing and required-variable validation hooks. Config example documents all keys from spec with defaults.

- [ ] **Step 1: Write verification checks (failing first where meaningful)**

Run: `bash -n setup.sh lib/common.sh` (expect fail/missing before creation), then after creation ensure it passes. Create a quick manual check: `./setup.sh --help` exits 0 and prints usage (to be implemented).
Expected: establishes executable/parseable skeleton.

- [ ] **Step 2: Implement `lib/common.sh`**

Include: strict-mode-friendly helpers (sourced), TTY-safe logging, `die()`, `require_root()`, OS detection via `/etc/os-release` allowing Ubuntu/Debian IDs (and compatible IDs/codenames as decided) else clear failure, helper `run_cmd`/`ensure_pkg` wrappers (minimal), idempotent helpers (`backup_file_once` or safe write helpers) as needed by later modules. No destructive behavior.
Run: `bash -n lib/common.sh`
Expected: PASS syntax.

- [ ] **Step 3: Implement `config/spectre-docker.conf.example` and config loading in `setup.sh`**

Document keys/defaults: `ADMIN_USER`, `ADMIN_SSH_PUBLIC_KEYS`, `SSH_PORT`, `SSH_PASSWORD_AUTH`, `SSH_PERMIT_ROOT_LOGIN`, `SSH_PUBKEY_AUTH`, `UFW_ALLOWED_TCP_PORTS`, `BACKUP_ENABLED`, `BACKUP_TARGET_DIR`, `BACKUP_PATHS`, `BACKUP_RETENTION_COUNT`, `BACKUP_SCHEDULE`, and an explicit lockout override (e.g. `ALLOW_LOCKOUT_RISK=no`). `setup.sh` finds config at `config/spectre-docker.conf` (or `--config` path), loads safely, applies defaults, validates required/sane values, prints help/usage, and (for now) runs preflight-only placeholder or no-op module loop.
Run: `bash -n setup.sh` and `./setup.sh --help`
Expected: usage shown, exit 0.

- [ ] **Step 4: Verify config validation behavior**

Create a temp config missing required safety info (e.g. password auth disabled, no keys, no override) and run `./setup.sh --config <tmp>` as non-root/root-appropriate simulation where possible; expect clear validation/lockout-safety error as designed. (If root-only actions block, at least validate parsing/logic path that does not require system mutation.)
Expected: clear, actionable failure; no system changes.

- [ ] **Step 5: Commit**

```bash
git add setup.sh lib/common.sh config/spectre-docker.conf.example config/.gitignore
git commit -m "feat: add spectre-docker bootstrap scaffold and config loading"
```

### Task 3: Implement preflight, users, and SSH hardening modules

**Files:**
- Create: `modules/00-preflight.sh`, `modules/10-users.sh`, `modules/20-ssh.sh`, `templates/sshd/99-spectre-docker.conf.tmpl` (or equivalent)
- Modify: `setup.sh` (invoke modules), `lib/common.sh` (helpers if needed)

**Interfaces:**
- Produces: modules callable in order, each idempotent. Preflight enforces root + supported OS + apt presence. Users ensures `ADMIN_USER`, sudo membership, `~/.ssh` perms, authorized keys installed. SSH writes managed drop-in with configured policy, enforces lockout safety, runs `sshd -t` before reload, reloads correct service name.

- [ ] **Step 1: Write/define checks for module behavior**

Prepare: syntax checks `bash -n modules/00-preflight.sh modules/10-users.sh modules/20-ssh.sh`; and a dry logic review against spec (lockout safety, `sshd -t` gate).
Expected: failing until implemented.

- [ ] **Step 2: Implement `00-preflight.sh` and `10-users.sh`**

`00-preflight`: confirm root, supported Ubuntu/Debian, apt-get available, basic environment. `10-users`: create user if missing, ensure sudo group membership (distro-appropriate `sudo` group), create `.ssh` with `700`, install authorized keys from config (file or inline) into `authorized_keys` with `600`, idempotent (no duplicates). Log actions.
Run: `bash -n modules/00-preflight.sh modules/10-users.sh`
Expected: PASS.

- [ ] **Step 3: Implement `20-ssh.sh` with managed drop-in and safety**

Render/write `/etc/ssh/sshd_config.d/99-spectre-docker.conf` from template/variables: `PermitRootLogin`, `PasswordAuthentication`, `PubkeyAuthentication`, `MaxAuthTries`, `PermitEmptyPasswords`, `Port`. Before applying restrictive auth, verify viable admin access (key present for admin) or honor explicit override else `die`. Run `sshd -t`; only then reload/restart service (`ssh` on Ubuntu, `sshd` on Debian as applicable—detect). Idempotent writes.
Run: `bash -n modules/20-ssh.sh`
Expected: PASS.

- [ ] **Step 4: Wire modules into `setup.sh` and verify**

Ensure deterministic order and that re-sourcing/rerun is safe. Run `bash -n setup.sh` and, if in a safe environment, `./setup.sh --help` and a config-validate-only path; on a disposable Ubuntu/Debian environment do a full run and re-run to confirm convergence (document if not runnable here).
Expected: scripts parse; behavior matches spec intent.

- [ ] **Step 5: Commit**

```bash
git add setup.sh lib/common.sh modules/00-preflight.sh modules/10-users.sh modules/20-ssh.sh templates/sshd
git commit -m "feat: add preflight, user provisioning, and SSH hardening modules"
```

### Task 4: Implement fail2ban, firewall (UFW), and Docker/port-exposure handling

**Files:**
- Create: `modules/30-fail2ban.sh`, `modules/40-firewall.sh`, `templates/fail2ban/jail.d/spectre-docker.local.tmpl`
- Modify: `setup.sh`, `lib/common.sh` if needed

**Interfaces:**
- Produces: fail2ban installed/enabled with SSH jail on configured port. UFW installed/enabled with default deny incoming/allow outgoing, rate-limited SSH allow, configured extra TCP ports allowed. Explicit handling so Docker-published ports are not unintentionally exposed beyond intent (e.g. UFW forward policy/after.rules and/or DOCKER-USER defaults) with documented approach in code comments/README notes later.

- [ ] **Step 1: Implement `30-fail2ban.sh`**

Install `fail2ban`, write jail config for `sshd` with correct port/logpath/backend defaults for distro, enable/restart service idempotently.
Run: `bash -n modules/30-fail2ban.sh`
Expected: PASS.

- [ ] **Step 2: Implement `40-firewall.sh`**

Install `ufw`, set defaults, allow/rate-limit SSH port, allow `UFW_ALLOWED_TCP_PORTS`, apply Docker exposure mitigation consistent with chosen mechanism and spec intent, enable UFW safely (ensure SSH rule present before enable), show/status logging. Idempotent rule application.
Run: `bash -n modules/40-firewall.sh`
Expected: PASS.

- [ ] **Step 3: Verify parsing and idempotent structure**

Run: `bash -n modules/30-fail2ban.sh modules/40-firewall.sh setup.sh`
Expected: PASS. Manually inspect for duplicate-appending logic (use `ufw status` checks or guarded adds).

- [ ] **Step 4: Commit**

```bash
git add modules/30-fail2ban.sh modules/40-firewall.sh templates/fail2ban setup.sh lib/common.sh
git commit -m "feat: add fail2ban and UFW firewall hardening modules"
```

### Task 5: Implement updates/time sync and Docker installation modules

**Files:**
- Create: `modules/50-updates.sh`, `modules/60-docker.sh`, `templates/docker/daemon.json`
- Modify: `setup.sh`, `lib/common.sh` if needed

**Interfaces:**
- Produces: unattended security upgrades enabled (distro-standard) and time sync active. Docker installed from official apt repo for detected distro/arch/codename, services enabled, `ADMIN_USER` in `docker` group, `/etc/docker/daemon.json` managed with log rotation defaults (and other safe defaults per spec) with restart only on change.

- [ ] **Step 1: Implement `50-updates.sh`**

Install/configure `unattended-upgrades` (and `apt-listchanges`/defaults as appropriate) for security updates; ensure time sync (`systemd-timesyncd` or existing default) enabled. Idempotent.
Run: `bash -n modules/50-updates.sh`
Expected: PASS.

- [ ] **Step 2: Implement `60-docker.sh`**

Remove conflicting packages if needed per Docker docs (carefully/idempotently), install prerequisites, add Docker GPG key and apt source for correct OS, install engine + CLI + containerd + buildx + compose plugin, enable/start docker, add user to docker group, write daemon.json (merge/managed) with log rotation (`max-size`/`max-file`) and reload/restart conditionally.
Run: `bash -n modules/60-docker.sh`
Expected: PASS.

- [ ] **Step 3: Verify template and wiring**

Run: `bash -n modules/50-updates.sh modules/60-docker.sh setup.sh` and validate `templates/docker/daemon.json` is valid JSON (e.g. `python3 -m json.tool templates/docker/daemon.json >/dev/null` or `jq .` if available).
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add modules/50-updates.sh modules/60-docker.sh templates/docker setup.sh lib/common.sh
git commit -m "feat: add security updates, time sync, and Docker install modules"
```

### Task 6: Implement backups module, script, and schedule

**Files:**
- Create: `modules/70-backups.sh`, `templates/backup/spectre-docker-backup.sh`, and schedule template (`templates/backup/spectre-docker-backup.cron` or systemd `templates/backup/spectre-docker-backup.service` + `.timer`) — choose one consistently
- Modify: `setup.sh`, config example if needed for clarity

**Interfaces:**
- Produces: installed backup executable at a known path (e.g. `/usr/local/sbin/spectre-docker-backup`) that archives configured/default paths to `BACKUP_TARGET_DIR` with timestamped `tar.gz` and prunes to `BACKUP_RETENTION_COUNT`; scheduled daily per config. Honors `BACKUP_ENABLED`. Restore procedure documented later.

- [ ] **Step 1: Implement backup script template/logic**

Script reads config or embedded defaults, validates paths/target, creates archive of explicit paths only, prunes old archives safely (matching naming pattern), logs results, exits non-zero on failure.
Run: `bash -n templates/backup/spectre-docker-backup.sh`
Expected: PASS.

- [ ] **Step 2: Implement `70-backups.sh`**

Create target/state dirs with secure perms, install script, install/enable chosen schedule (cron entry or systemd timer) idempotently, skip/disable cleanly if `BACKUP_ENABLED=no` as appropriate.
Run: `bash -n modules/70-backups.sh`
Expected: PASS.

- [ ] **Step 3: Verify end-to-end wiring**

Run: `bash -n setup.sh modules/70-backups.sh` and a local dry invocation of backup script logic against temp dirs/config if supported (no privileged system paths).
Expected: archive/prune behavior correct for sample inputs.

- [ ] **Step 4: Commit**

```bash
git add modules/70-backups.sh templates/backup config/spectre-docker.conf.example setup.sh
git commit -m "feat: add scheduled backup module and scripts"
```

### Task 7: Rewrite documentation, metadata, and repository automation

**Files:**
- Modify: `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `AGENTS.md`
- Modify/Remove: `.github/workflows/*`, `.github/ISSUE_TEMPLATE/*`, `.github/pull_request_template.md`, `.github/dependabot.yml`, `.githooks/*`, `.devin/*` as appropriate
- Modify: `LICENSE` (keep, update holders/year only if clearly appropriate)

**Interfaces:**
- Produces: coherent `spectre-docker` documentation (quick start: clone, copy/edit config, run `sudo ./setup.sh`; config reference; security/Docker-UFW notes; backup/restore; supported OS; re-run/idempotency). CI/automation reflects bash bootstrap (e.g. shellcheck, `bash -n`, formatting checks) or is removed if not meaningful.

- [ ] **Step 1: Update CI/workflows and repo automation**

Remove Node/app/compose-specific CI jobs. Add lightweight checks if feasible (syntax check all `*.sh`, shellcheck if tool available in CI). Update dependabot to relevant ecosystems or remove stale ones.
Run: inspect workflow YAML for validity.
Expected: no references to removed app/tests.

- [ ] **Step 2: Rewrite `README.md` and core docs**

Cover intent, requirements, quick start, config keys, what gets hardened/installed, backup/restore, Docker group/UFW notes, troubleshooting, and that users deploy their own apps. Update CONTRIBUTING/SECURITY/CHANGELOG/AGENTS to match new scope and remove stack instructions.
Run: `rg -n "spectre-server-layer|nginx|/api/|smoke-test.sh" README.md CONTRIBUTING.md SECURITY.md AGENTS.md || true`
Expected: docs aligned with spectre-docker.

- [ ] **Step 3: Final verification pass**

Run: `bash -n setup.sh lib/common.sh modules/*.sh templates/backup/spectre-docker-backup.sh` (and any other bash scripts); `find . -name "*.sh" -print0 | xargs -0 -n1 bash -n`; search for stale names `rg -n "spectre-server-layer" . || true`; confirm `config/spectre-docker.conf` is ignored.
Expected: all scripts parse, no stale identity, clean structure.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: finalize spectre-docker documentation and automation"
```

---

## Self-Review

**1. Spec coverage:** rename/remove stack (Task 1), config-driven scaffold (Task 2), users/SSH/fail2ban (Tasks 3-4), firewall+Docker exposure (Task 4), updates/time (Task 5), Docker install/hardening (Task 5), backups/schedule/restore docs (Tasks 6-7), docs/CI/meta alignment (Task 7), idempotency/validation/OS checks embedded across tasks — covered.

**2. Step scan:** steps include concrete commands/checks and file targets; implementation bodies left to engineer guided by signatures/intent (acceptable for bash modules). No "TBD" steps.

**3. Type consistency:** N/A (Bash) — consistent naming for config keys, paths, module/script names maintained.

**4. Review Focus:** lockout safety and `sshd -t` exercised in Tasks 2-3; Docker/UFW exposure handled in Task 4 and documented in Task 7; idempotency called out in each module task and verified on re-run where possible; unsupported OS/no-root/error paths in Task 2-3 preflight/validation; config validation/unsafe inputs in Task 2. No additional uncovered high-risk classes identified beyond these; implementers must include negative-case checks during Task 2/3 verification.

**5. Proportion:** plan is longer than spec due to task decomposition and commands, but focuses on decisions, files, interfaces, and verifications rather than full function bodies.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-11-11-spectre-docker.md`. Please review the plan. Which execution approach would you prefer?

- **Subagent-driven** - A fresh subagent implements each task and a fresh reviewer checks it before the next one starts, then a whole-branch review at the end. Most thorough; costs a fresh context per task and per review.
- **Native** - I implement every task myself in this session, the way this harness runs work, then one fresh reviewer on the most capable model checks the whole branch. Cheapest and fastest; no independent review until the end. Runs well with a mid-tier session model, since the plan carries the design.

For this plan I recommend **Native**, because the tasks are sequential and tightly coupled refactors of the same repo (rename/replace, then layered modules building on shared lib/config), with 7 sizable tasks where coordination overhead of per-task subagents outweighs benefit, and a full-branch review can catch cross-cutting issues. Does the plan capture what you want, and which approach should we use?
