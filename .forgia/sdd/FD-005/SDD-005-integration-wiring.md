---
id: "SDD-005"
fd: "FD-005"
title: "Integration wiring + scenario lifecycle"
status: assigned
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-18"
started: ""
completed: ""
tags: [pki, integration, wiring, scenario]
---

# SDD-005: Integration wiring + scenario lifecycle

> Parent FD: [[FD-005]]
> Depends on: [[SDD-001]], [[SDD-002]], [[SDD-003]], [[SDD-004]] (all previous SDDs)
> Consumed by: none (final SDD in chain)

## Scope

Integration wiring SDD. Create the `scenarios/scen-pki-ca/` directory structure with setup, teardown, and test orchestration. Add mise tasks for the scenario lifecycle. Ensure the main `mise run all` (59 tests) is unaffected. Include documentation with production considerations.

What to build:

1. **Directory structure**:
   ```
   scenarios/scen-pki-ca/
     scripts/
       setup-pki.sh       # From SDD-001: mount engines, generate CA chain
       setup-roles.sh      # From SDD-002: create PKI roles
       teardown-pki.sh     # Disable engines, clean up
     README.md             # Scenario description + production considerations
   ```

2. **Mise tasks** (in `mise.toml` or `scenarios/scen-pki-ca/mise.toml`):
   - `scen:pki-ca:setup` -- runs setup-pki.sh then setup-roles.sh
   - `scen:pki-ca:test` -- runs `bats tests/09-pki.bats`
   - `scen:pki-ca:teardown` -- runs teardown-pki.sh (disable pki-root/ and pki-k8s/ engines)
   - `scen:pki-ca:all` -- setup + test + teardown in sequence

3. **Teardown script** `scenarios/scen-pki-ca/scripts/teardown-pki.sh`:
   - Disable `pki-k8s/` engine
   - Disable `pki-root/` engine
   - Idempotent (checks if engines exist before disabling)

4. **README** `scenarios/scen-pki-ca/README.md`:
   - Scenario description
   - Prerequisites (OpenBao running, VAULT_ADDR/VAULT_TOKEN set)
   - Usage (`mise run scen:pki-ca:all`)
   - Production Considerations section

5. **Main `mise run all` unaffected** -- scenario tests are opt-in via `scen:pki-ca:*` tasks

## Interfaces

| Interface | Type | Description |
|-----------|------|-------------|
| `mise run scen:pki-ca:setup` | mise task | Runs PKI setup + role creation scripts |
| `mise run scen:pki-ca:test` | mise task | Runs BATS tests for PKI scenario |
| `mise run scen:pki-ca:teardown` | mise task | Cleans up PKI engines |
| `mise run scen:pki-ca:all` | mise task | Full lifecycle: setup, test, teardown |
| `scenarios/scen-pki-ca/scripts/teardown-pki.sh` | shell script | Disables PKI engines |
| `scenarios/scen-pki-ca/README.md` | documentation | Scenario docs + production considerations |

## Constraints

- Language: Bash with `set -euo pipefail` for scripts, TOML for mise tasks
- Dependencies: `mise`, `vault` CLI, `bats`, `openssl`
- Main `mise run all` must NOT include PKI scenario tests (opt-in only)
- Teardown must be safe to run even if setup was partial or never ran

### Security (from threat model)

- Document plaintext-on-wire risk: lab uses HTTP for Vault, production MUST use TLS
- Document production requires TLS on OpenBao listener
- Document production requires HTTPS for CRL distribution points
- Document cert-manager Vault Issuer as the production bridge (not direct vault CLI)
- Include Production Considerations section in README

## Best Practices

- All scripts use `set -euo pipefail`
- Teardown is idempotent and handles partial state gracefully
- Mise tasks use `depends` for sequencing (setup before test, test before teardown in `all`)
- Scenario is self-contained: no side effects on other tests or scenarios
- README includes clear prerequisites and usage instructions

## Test Requirements

| Type | What | Coverage |
|------|------|----------|
| Integration | `mise run scen:pki-ca:setup` completes without error | 1 test |
| Integration | `mise run scen:pki-ca:test` runs all BATS tests and passes | 1 test |
| Integration | `mise run scen:pki-ca:teardown` completes without error | 1 test |
| Integration | `mise run scen:pki-ca:all` full lifecycle passes | 1 test |
| Integration | Main `mise run all` still reports 59 tests (unaffected) | 1 test |
| Smoke | Teardown is idempotent: running twice does not error | 1 test |

**Minimum: 6 integration/smoke tests** (manual verification acceptable for lifecycle tests)

## Acceptance Criteria

- [ ] `scenarios/scen-pki-ca/` directory exists with scripts/ and README.md
- [ ] `setup-pki.sh` mounts engines and creates CA chain (from SDD-001)
- [ ] `setup-roles.sh` creates 4 PKI roles (from SDD-002)
- [ ] `teardown-pki.sh` disables both PKI engines, is idempotent
- [ ] Mise tasks `scen:pki-ca:{setup,test,teardown,all}` work correctly
- [ ] `mise run scen:pki-ca:all` runs full lifecycle successfully
- [ ] Main `mise run all` (59 tests) is unaffected
- [ ] README includes production considerations (TLS, HTTPS CRL, cert-manager bridge)
- [ ] All scripts use `set -euo pipefail`

## Context

- [ ] `.forgia/fd/FD-005-pki-ca-engine-k8s-certs.md` -- Feature Design
- [ ] `.forgia/fd/FD-005-threat-model.md` -- STRIDE threat model
- [ ] `tests/07-openbao.bats` -- reference BATS structure
- [ ] `manifests/plugins/kustomize/openbao-tenant-template/vault-cr-template.yaml` -- Vault CR template
- [ ] K8s PKI requirements: https://kubernetes.io/docs/setup/best-practices/certificates/

## Constitution Check

- [x] Respects code standards (YAML 2-space, shell `set -euo pipefail`)
- [x] Respects commit conventions (`feat(FD-005): ...`)
- [x] No hardcoded secrets (CA keys never in files, only in OpenBao internal storage)
- [x] Tests defined and sufficient (6 integration tests + production docs)

---

## Work Log

### Agent

- **Executor**: <!-- openhands | claude-code | manual -->
- **Started**: <!-- timestamp -->
- **Completed**: <!-- timestamp -->
- **Duration**: <!-- total time -->

### Decisions

1. <!-- decision 1: what and why -->

### Output

- **Commit(s)**: <!-- hash -->
- **PR**: <!-- link -->
- **Files created/modified**:
  - `path/to/file`

### Retrospective

- **What worked**:
- **What didn't**:
- **Suggestions for future FDs**:
