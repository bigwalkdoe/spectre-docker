## Summary

<!-- One paragraph: what does this change and why. -->

## Checks

- [ ] `bash -n` passes for changed shell scripts
- [ ] `shellcheck -S style` passes for changed shell scripts (if available)
- [ ] Bootstrap behavior remains idempotent and safe to re-run where applicable
- [ ] No secrets or real local config committed (`config/spectre-docker.conf` stays local)
- [ ] README / `config/spectre-docker.conf.example` updated if behavior or config changed
- [ ] Security-sensitive defaults were not weakened without explicit, documented opt-in

## Notes for reviewers

<!-- Anything non-obvious: distro-specific behavior, lockout/firewall implications, rollback considerations. -->

## Risk

<!-- Default "low". If non-trivial, describe impact and mitigation. -->
