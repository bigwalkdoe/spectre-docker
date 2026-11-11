# spectre-k8s — companion project plan (outline)

`spectre-k8s` is the planned Kubernetes-focused companion to `spectre-docker`. This document captures an initial scope to bootstrap that separate repository/project.

## Intent
Provide an opinionated, config-driven bootstrap for fresh Ubuntu/Debian servers to run Kubernetes workloads with a secure baseline, similar in ergonomics to `spectre-docker` (clone, configure, run) but tailored to Kubernetes.

## Proposed scope (initial)
- **Target:** Ubuntu/Debian LTS/stable servers (single-node first; multi-node as a later consideration).
- **Distribution choice:** select a lightweight, supportable Kubernetes distribution for single-node/server use (evaluate `k3s` first; document alternatives such as `microk8s` or kubeadm-based setups).
- **Baseline reuse:** carry over applicable hardening from `spectre-docker` (users/SSH, firewall, unattended upgrades, fail2ban, backups of host/config state) with Kubernetes-aware networking/firewall rules.
- **Kubernetes install:** install/configure chosen distribution, kubeconfig access for admin user, and basic cluster readiness checks.
- **Runtime/networking:** define defaults for container runtime and CNI as implied by the chosen distro; document port/firewall requirements (API server, node, CNI, ingress).
- **Storage/ingress (optional/later):** decide minimal defaults (e.g. local-path storage, ingress controller) as explicit modules/options.
- **Operations:** idempotent modules, config-driven setup, dry-run/validation, upgrade and backup/restore guidance for cluster state where applicable.

## Non-goals (initial)
- Managed Kubernetes control planes or cloud-provider provisioning APIs.
- Full multi-cluster fleet management.
- Opinionated application deployment pipelines beyond preparing the cluster.

## Suggested next steps
1. Create the `spectre-k8s` repository with structure inspired by `spectre-docker` (`setup.sh`, `lib/`, `modules/`, `templates/`, `config/`, docs).
2. Decide and document the Kubernetes distribution and supported topologies (single-node default).
3. Define config schema and firewall/port matrix for the chosen distro.
4. Implement baseline + Kubernetes modules incrementally with validation on fresh hosts.
5. Add CI (shell checks), documentation, and an operations/validation checklist similar to `docs/validation.md`.
