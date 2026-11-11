# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
- Renamed and repurposed the project from **spectre-server-layer** (a sample Docker Compose stack) to **spectre-docker**, an opinionated Ubuntu/Debian server bootstrap for installing and hardening Docker and a secure host baseline.
- Removed the former sample application stack (nginx/app/postgres/redis), stack scripts, and stack-specific configuration.

### Added
- Config-driven, modular, idempotent bootstrap (`setup.sh`, `lib/common.sh`, ordered modules, templates).
- Baseline hardening: non-root admin user provisioning, SSH hardening with lockout safety, fail2ban for SSH, UFW firewall defaults with conservative Docker forwarding restrictions, unattended security upgrades, and time synchronization.
- Docker Engine and Compose plugin installation from official repositories with daemon log-rotation defaults.
- Scheduled, configurable backups (`/usr/local/sbin/spectre-docker-backup`) with retention pruning and documented restore guidance.
- Updated documentation and CI checks for shell scripts.
