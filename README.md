# spectre-docker

`spectre-docker` is an opinionated, config-driven bootstrap for fresh **Ubuntu** and **Debian** servers. It installs and hardens Docker Engine (with the Compose plugin) and applies a secure baseline (users/SSH, firewall, fail2ban, unattended upgrades, backups) so you can deploy your own applications on a prepared host.

> This repository is being transformed from the former `spectre-server-layer` sample stack into a pure server bootstrap. Setup modules and full documentation are being added.

## Status

Implementation in progress. See:
- Design: `docs/superpowers/specs/2026-11-11-spectre-docker-design.md`
- Plan: `docs/superpowers/plans/2026-11-11-spectre-docker.md`

## Planned quick start

```bash
git clone <this-repo> && cd spectre-docker
cp config/spectre-docker.conf.example config/spectre-docker.conf
# edit config/spectre-docker.conf
sudo ./setup.sh
```

## License

MIT. See [LICENSE](LICENSE).
