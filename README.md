# spectre-docker

`spectre-docker` is an opinionated, config-driven bootstrap for fresh **Ubuntu** and **Debian** servers. It installs and hardens **Docker Engine** (with the Compose plugin) and applies a secure host baseline so you can deploy and run your own applications, databases, and software on a prepared machine.

- **Config-driven:** edit one file, run one command.
- **Idempotent:** safe to re-run; modules converge state.
- **Auditable:** modular Bash scripts, no heavy control-plane dependencies.
- **Not an app runner:** `spectre-docker` prepares the host; deploying/starting your workloads is up to you.

## Supported systems

- Ubuntu and Debian (currently supported LTS/stable releases, e.g. Ubuntu 22.04/24.04+, Debian 12+)
- `systemd`-based systems with `apt`
- Root (or sudo) access and outbound network access for package installation

The setup will detect unsupported systems and exit with a clear error.

## Quick start

```bash
git clone <this-repo> spectre-docker
cd spectre-docker

cp config/spectre-docker.conf.example config/spectre-docker.conf
# edit config/spectre-docker.conf (set ADMIN_SSH_PUBLIC_KEYS, review defaults)

sudo ./setup.sh
```

After completion, verify you can log in as the configured admin user over SSH (in a separate session) before closing your current session. If the admin user was added to the `docker` group, log out/in for group membership to take effect.

## Configuration

Real configuration lives in `config/spectre-docker.conf` (gitignored). Copy from `config/spectre-docker.conf.example`.

| Key | Default | Description |
| --- | --- | --- |
| `ADMIN_USER` | `deploy` | Non-root admin/deploy user to create/ensure (added to `sudo` and `docker`) |
| `ADMIN_SSH_PUBLIC_KEYS` | *(empty)* | Path to a file of public key(s), or inline public key material, for `ADMIN_USER` |
| `SSH_PORT` | `22` | SSH port |
| `SSH_PASSWORD_AUTH` | `no` | Allow password auth (`yes`/`no`, explicit opt-in to enable) |
| `SSH_PERMIT_ROOT_LOGIN` | `no` | `PermitRootLogin` value (`no`, `yes`, `prohibit-password`, `forced-commands-only`) |
| `SSH_PUBKEY_AUTH` | `yes` | Enable public key auth |
| `ALLOW_LOCKOUT_RISK` | `no` | Must be `yes` to override lockout safety when password auth is disabled without a viable admin key |
| `UFW_ALLOWED_TCP_PORTS` | *(empty)* | Extra inbound TCP ports to allow (space-separated), e.g. `"80 443"` (SSH is allowed automatically) |
| `BACKUP_ENABLED` | `yes` | Enable scheduled backups (`yes`/`no`) |
| `BACKUP_TARGET_DIR` | `/var/backups/spectre-docker` | Directory for backup archives (can be a mounted path) |
| `BACKUP_PATHS` | `/etc /etc/spectre-docker` | Space-separated paths to back up (explicit; app data not guessed) |
| `BACKUP_RETENTION_COUNT` | `7` | Number of archives to retain |
| `BACKUP_SCHEDULE` | `daily` | `daily`, `hourly`, or a 5-field cron expression |

## What the bootstrap does

Modules run in order and converge system state:

1. **Preflight** (`modules/00-preflight.sh`): verifies root, supported Ubuntu/Debian, `apt`, and `systemd`.
2. **Users** (`modules/10-users.sh`): ensures `ADMIN_USER` exists, grants sudo membership, secures `~/.ssh`, installs authorized keys idempotently.
3. **SSH hardening** (`modules/20-ssh.sh`): installs a managed drop-in at `/etc/ssh/sshd_config.d/99-spectre-docker.conf` (port, root login, password/pubkey auth, sane limits), enforces lockout safety, validates with `sshd -t` before reload, and reloads the SSH service.
4. **Fail2ban** (`modules/30-fail2ban.sh`): installs and configures fail2ban to protect SSH on the configured port.
5. **Firewall** (`modules/40-firewall.sh`): configures UFW (default deny incoming / allow outgoing), rate-limits SSH, allows configured extra ports, and applies conservative Docker forwarding restrictions.
6. **Updates & time** (`modules/50-updates.sh`): enables unattended security upgrades and ensures time synchronization.
7. **Docker** (`modules/60-docker.sh`): installs Docker Engine, CLI, containerd, Buildx, and Compose plugin from Docker’s official apt repository; enables services; adds `ADMIN_USER` to the `docker` group; manages `/etc/docker/daemon.json` (log rotation).
8. **Backups** (`modules/70-backups.sh`): installs `/usr/local/sbin/spectre-docker-backup` and a cron schedule; creates timestamped `tar.gz` archives of configured paths and prunes by retention.

A copy of the applied config is stored at `/etc/spectre-docker/spectre-docker.conf` for managed state/backup tooling.

## Security notes

- **SSH lockout safety:** with `SSH_PASSWORD_AUTH=no` (default), setup fails if no admin public key is configured/found and no existing authorized keys are present, unless `ALLOW_LOCKOUT_RISK=yes` is explicitly set. Always keep a working out-of-band/console access path when changing SSH settings.
- **UFW and Docker:** Docker can manipulate firewall rules in ways that bypass naive UFW expectations for published container ports. `spectre-docker` applies conservative forwarding restrictions (DOCKER-USER / forward policy hardening) to reduce unintended exposure, but firewall behavior can vary by distro, backend (iptables/nftables), and Docker changes. **Explicitly review and control any ports you publish** (`-p`/Compose `ports`) and validate exposure from outside the host.
- **Docker group:** membership in the `docker` group grants root-equivalent access on the host; add only trusted users.

## Backups and restore

- Backups are **explicit**: only paths listed in `BACKUP_PATHS` (plus defaults like `/etc` and `/etc/spectre-docker`) are archived. Application data is not discovered automatically.
- Archives are written to `BACKUP_TARGET_DIR` as `spectre-docker-<host>-<timestamp>.tar.gz` and pruned to `BACKUP_RETENTION_COUNT`.
- To run a backup manually: `sudo /usr/local/sbin/spectre-docker-backup`
- To list archives: `ls -lt /var/backups/spectre-docker`
- **Restore (example):** extract needed files from an archive after reviewing contents:
  ```bash
  sudo tar -tzf /var/backups/spectre-docker/spectre-docker-<host>-<timestamp>.tar.gz
  sudo tar -xzpf /var/backups/spectre-docker/spectre-docker-<host>-<timestamp>.tar.gz -C / <path/to/restore>
  ```
  Restore carefully (especially `/etc` contents and service configs) and reload/restart affected services as appropriate. Test restores in a safe environment.

## Idempotency and re-runs

Re-running `sudo ./setup.sh` is supported. Modules aim to converge state without duplicating configuration entries, rules, or scheduled jobs, and to restart/reload services only when changes are applied.

## Repository layout

- `setup.sh` — main entrypoint
- `config/spectre-docker.conf.example` — example configuration
- `lib/common.sh` — shared helpers (logging, OS detection, config loading/validation)
- `modules/` — ordered, single-responsibility modules
- `templates/` — managed config/script templates
- `docs/` — design and plans

## Development checks

```bash
find . -name "*.sh" -type f -print0 | xargs -0 -n1 bash -n
# if available:
# shellcheck -S style setup.sh lib/*.sh modules/*.sh templates/backup/spectre-docker-backup.sh
```

## License

MIT. See [LICENSE](LICENSE).
