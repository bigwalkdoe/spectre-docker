# spectre-docker validation checklist

Use this checklist to validate `spectre-docker` on fresh **Ubuntu** and **Debian** hosts (e.g. Ubuntu 22.04/24.04 LTS, Debian 12). Run on disposable or snapshot-backed instances where possible.

## Preparation
- [ ] Provision a fresh host and confirm OS: `cat /etc/os-release`
- [ ] Ensure outbound network access and sudo/root access
- [ ] Clone repo and create config:
  ```bash
  git clone https://github.com/bigwalkdoe/spectre-docker.git
  cd spectre-docker
  cp config/spectre-docker.conf.example config/spectre-docker.conf
  ```
- [ ] Set `ADMIN_SSH_PUBLIC_KEYS` (file path or inline key) and review ports/schedule/settings

## First run
- [ ] Run: `sudo ./setup.sh`
- [ ] Confirm exit code 0 and summary shows modules run
- [ ] **Do not close current session yet** — verify SSH access in a separate session as `ADMIN_USER` on `SSH_PORT`

## Baseline checks
- [ ] User/groups: `id <ADMIN_USER>` includes `sudo` and `docker`
- [ ] SSH effective config: `sudo sshd -T | egrep 'port|permitrootlogin|passwordauthentication|pubkeyauthentication|maxauthtries'`
- [ ] SSH service active: `systemctl is-active ssh || systemctl is-active sshd`
- [ ] UFW: `sudo ufw status verbose` (default deny incoming, SSH limited, extra ports as configured)
- [ ] Fail2ban: `sudo fail2ban-client status sshd` (or configured jail)
- [ ] Unattended upgrades/time sync: `systemctl is-active unattended-upgrades` and `timedatectl status`
- [ ] Docker: `docker --version`, `docker compose version`, `systemctl is-active docker`
- [ ] Daemon config: `cat /etc/docker/daemon.json` (log rotation present)
- [ ] Docker functional (as `ADMIN_USER` after re-login/group refresh): `docker run --rm hello-world`

## Idempotency
- [ ] Re-run: `sudo ./setup.sh`
- [ ] Confirm no errors, minimal/no unnecessary restarts, no duplicate authorized keys, cron entries, or UFW rule growth
- [ ] Spot-check managed files unchanged when config unchanged: `/etc/ssh/sshd_config.d/99-spectre-docker.conf`, `/etc/fail2ban/jail.d/spectre-docker.local`, `/etc/cron.d/spectre-docker-backup`, `/etc/docker/daemon.json`

## Backups
- [ ] Manual run: `sudo /usr/local/sbin/spectre-docker-backup`
- [ ] Archive created in `BACKUP_TARGET_DIR`: `ls -lt /var/backups/spectre-docker`
- [ ] Inspect contents: `sudo tar -tzf <archive> | head`
- [ ] Retention: create > `BACKUP_RETENTION_COUNT` archives (manual runs) and confirm pruning
- [ ] Restore drill (safe path): extract a sample file from archive to a temp location and compare

## Firewall/Docker exposure (important)
- [ ] From another host, confirm only intended ports are reachable
- [ ] Test a published container port (e.g. `docker run --rm -d -p 8080:80 nginx`) and verify external reachability matches your security expectations given UFW/DOCKER-USER behavior; document observations per distro/backend

## Negative/safety checks (controlled)
- [ ] Invalid config syntax/value is rejected clearly
- [ ] Lockout safety: `SSH_PASSWORD_AUTH=no` without keys/override fails before applying risky state
- [ ] Unsupported OS (if testable) fails clearly

## Record results
- OS/version, kernel, iptables/nftables backend, Docker version, any deviations, and logs/output for failures.
