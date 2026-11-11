# Contributing to spectre-docker

Thanks for your interest in contributing.

`spectre-docker` is a Bash-based, idempotent bootstrap for preparing fresh Ubuntu/Debian servers (Docker installation/hardening and a secure baseline). Changes must preserve safety, idempotency, and clarity.

## Guidelines

- Keep changes focused and reviewable.
- Target **Ubuntu and Debian**; detect unsupported systems and fail clearly.
- Scripts must be safe to re-run (idempotent) and avoid destructive behavior by default.
- Fail safely on security-sensitive paths (SSH/lockout, firewall, config validation).
- Do not commit secrets or real local configuration (`config/spectre-docker.conf` is local).
- Prefer simple, auditable shell over unnecessary dependencies.

## Checks

Run before submitting:

```bash
find . -name "*.sh" -type f -print0 | xargs -0 -n1 bash -n
# if available:
# shellcheck -S style setup.sh lib/*.sh modules/*.sh templates/backup/spectre-docker-backup.sh
```

If you change behavior or configuration, update `README.md` and `config/spectre-docker.conf.example` accordingly.

## Commits and pull requests

- Use clear, imperative commit messages.
- Describe what changed and why, and call out any security-impacting behavior.
- Follow the repository pull request template.
