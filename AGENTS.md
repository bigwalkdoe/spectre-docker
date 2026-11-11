# Agent Instructions

## Purpose
This file provides guidance to AI agents working in this repository. Follow these instructions to maintain consistency, quality, and safety.

## Project context
`spectre-docker` is an opinionated, config-driven Bash bootstrap for fresh **Ubuntu/Debian** servers. It installs and hardens Docker Engine (+ Compose plugin) and applies a secure host baseline (users/SSH, firewall, fail2ban, updates, backups). It does **not** deploy or run user applications.

## Core Principles
- Understand before changing: read relevant code, docs, and the spec/plan before modifying behavior
- Make minimal, focused changes that solve the stated problem
- Follow existing patterns, conventions, and architecture
- Test and verify your changes (syntax checks, linting, and safe dry validation where possible)
- Leave the codebase better than you found it

## Repository Exploration
Before making significant changes:
1. Read `README.md`, `config/spectre-docker.conf.example`, and relevant scripts/modules
2. Understand structure (`setup.sh`, `lib/`, `modules/`, `templates/`, `config/`)
3. Check git history and current branch state

## Development Workflow
1. **Inspect** - Understand what needs to change
2. **Plan** - Break down the task into clear steps
3. **Implement** - Make changes following existing patterns
4. **Test** - Run relevant checks (e.g. `bash -n`, `shellcheck` if available)
5. **Verify** - Ensure behavior is correct and idempotent
6. **Review** - Check for unintended side effects

## Code Quality
- Write clear, auditable shell scripts (`set -euo pipefail` where appropriate)
- Keep modules single-responsibility and idempotent
- Handle errors with clear messages; fail safely (especially around SSH/lockout and firewall)
- Avoid over-engineering and unnecessary dependencies

## Safety Rules
- Never commit secrets or real local configuration (`config/spectre-docker.conf` is local/gitignored)
- Do not weaken security defaults silently; risky options must be explicit opt-in
- Be careful with destructive operations and system-level changes
- Ask for clarification on high-risk or ambiguous changes

## Git Practices
- Make atomic, well-described commits
- Check `git status` before committing
- Keep changes focused and reviewable

## Communication
- Be concise and focused
- Explain what you changed and why
- Report verification steps and results
- Flag any issues or concerns
