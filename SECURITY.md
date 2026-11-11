# Security Policy

## Supported versions

Security fixes are applied to the current `main` branch.

## Reporting a vulnerability

Please **do not** open a public issue for a security problem.

If private vulnerability reporting is enabled for this repository, use GitHub's **Report a vulnerability** flow (Security tab). Otherwise, contact the maintainers privately with:

- a description of the issue and affected component(s)
- affected commit/version
- reproduction steps or proof of concept (if safe to share)
- impact assessment and suggested remediation, if known

## Scope notes

`spectre-docker` configures system security settings (SSH, firewall, users, Docker, updates, backups). Treat changes that could weaken defaults, expose ports, or risk lockout/data loss as security-sensitive and document them clearly.
