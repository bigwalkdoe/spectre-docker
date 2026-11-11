# Contributing to spectre-docker

Thanks for your interest in contributing.

`spectre-docker` is a Bash-based, idempotent bootstrap for preparing fresh Ubuntu/Debian servers (Docker installation/hardening and a secure baseline). Changes should preserve safety, idempotency, and clarity.

## Guidelines

- Keep changes focused and reviewable.
- Target **Ubuntu and Debian**; detect unsupported systems and fail clearly.
- Scripts must be safe to re-run (idempotent) and avoid destructive behavior by default.
- Do not commit secrets or real local configuration (`config/spectre-docker.conf` is local).
- Prefer simple, auditable shell over unnecessary dependencies.

## Checks

When modifying shell scripts, run at least:

```bash
bash -n setup.sh lib/*.sh modules/*.sh 2>/dev/null || true
find . -name "*.sh" -type f -print0 | xargs -0 -n1 bash -n
# if available:
# shellcheck -S style setup.sh lib/*.sh modules/*.sh
```

Document behavior and config changes in `README.md` and `config/spectre-docker.conf.example` as appropriate.

## Commits and pull requests

- Use clear, imperative commit messages.
- Describe what changed and why, and note any security-impacting behavior.
- Follow the repository pull request template when opening a PR.
