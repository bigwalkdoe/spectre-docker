# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
- Renamed and repurposed the project from **spectre-server-layer** (a sample Docker Compose stack) to **spectre-docker**, a general-purpose Ubuntu/Debian server bootstrap for installing and hardening Docker and a secure host baseline.
- Removed the former sample application stack (nginx/app/postgres/redis), stack scripts, and stack-specific configuration in favor of modular, idempotent bootstrap scripts and config-driven setup.

### Added
- Initial design and implementation plan for `spectre-docker` (bootstrap scaffold, hardening modules, backups, and documentation) — in progress.
