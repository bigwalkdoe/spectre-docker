# Security Policy

## Supported versions

Security fixes are applied to the current `main` branch.

## Reporting a vulnerability

Please **do not** open a public issue for a security problem.

If private vulnerability reporting is enabled for this repository, use GitHub's **Report a vulnerability** flow (Security tab). Otherwise, contact the maintainers privately with:

- a description of the issue and affected component(s)
- affected commit/version and target OS (Ubuntu/Debian release)
- reproduction steps or proof of concept (if safe to share)
- impact assessment and suggested remediation, if known

## Scope notes

`spectre-docker` configures system security settings (users, SSH, firewall, fail2ban, Docker, updates, backups). Reports involving lockout risk, unintended port exposure (including Docker/UFW interactions), privilege escalation, unsafe config handling, or data-loss paths in backups are especially relevant.
