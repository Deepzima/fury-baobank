---
id: "SDD-004"
fd: "FD-004"
title: "BATS test suite + integration wiring"
status: assigned
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-18"
started: ""
completed: ""
tags: [bats, integration, wiring, scenario]
---

# SDD-004: BATS test suite + integration wiring

> Parent FD: [[FD-004]]

## Scope

Create the BATS integration test suite and mise task wiring for the cross-cluster secret injection scenario. This SDD ties together SDD-001 through SDD-003 into a testable, reproducible flow.

Deliverables:

1. **BATS test suite**: `tests/08-cross-cluster.bats` — integration tests covering the full scenario end-to-end:
   - Consumer cluster `fury-baobank-consumer` is running
   - OpenBao on baobank is reachable from the consumer cluster (network connectivity)
   - AppRole auth works cross-cluster (login from consumer context returns a valid token)
   - vault-env secret injection works (app pod starts with correct env var)
   - App pod has `DB_PASSWORD=s3cret`
   - Security: non-vault ServiceAccounts cannot read the AppRole credentials Secret
   - Security: AppRole token TTL is limited (<= 1h)
2. **Mise tasks** (in `mise.toml` or scenario-specific config):
   - `scen:secret-inject:up` — creates consumer cluster, provisions AppRole, deploys consumer app
   - `scen:secret-inject:test` — runs `tests/08-cross-cluster.bats`
   - `scen:secret-inject:down` — destroys consumer cluster, cleans up AppRole and test secrets
3. **Scenario isolation**: these tests and tasks are scenario-specific. They do NOT run as part of `mise run all` (the main 59-test suite). They require both clusters to be running.

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|-------------------------|-------------|---------------------------|
| `tests/08-cross-cluster.bats` | BATS test file | Integration tests for cross-cluster secret injection |
| `scen:secret-inject:up` | Mise task | Orchestrates SDD-001 + SDD-002 + SDD-003 in sequence |
| `scen:secret-inject:test` | Mise task | Runs `bats tests/08-cross-cluster.bats` |
| `scen:secret-inject:down` | Mise task | Destroys consumer cluster, cleans up baobank AppRole config |
| `tests/helpers.bash` (or `tests/helpers`) | BATS helper | Shared helper functions (existing) — reused for `wait_for`, `kctl`, etc. |

## Constraints / Vincoli

- Language / Linguaggio: Bash (BATS), TOML (mise)
- Framework: BATS (bats-core), mise
- Dependencies / Dipendenze: SDD-001 (consumer cluster), SDD-002 (AppRole), SDD-003 (consumer app). Both Kind clusters must be running. `bats`, `kubectl`, `vault` CLI available.
- Patterns / Pattern: BATS test structure follows `tests/07-openbao.bats` (load helpers, `setup_file`/`teardown_file`, `@test` blocks). `set -euo pipefail` in mise task scripts.

### Security (from threat model)

- **Test `auth can-i get secrets` for non-vault SAs fails**: on the consumer cluster, verify that the `default` ServiceAccount in the consumer namespace cannot read the `approle-credentials` Secret. Only the app's ServiceAccount (if RBAC is configured) should have access.
- **Verify AppRole token TTL is limited**: after AppRole login, inspect the token and assert TTL <= 3600s.
- **Document no-TLS risk**: include a comment in the BATS file explicitly noting that Vault API traffic is plaintext over the Docker bridge. This is a lab-only accepted risk.

## Best Practices

- Error handling: BATS `setup_file` should check that both clusters exist before running tests. `teardown_file` should clean up gracefully (best-effort, `|| true` on cleanup commands).
- Naming: test names are descriptive sentences (e.g., `@test "consumer cluster is running"`). Mise tasks use `scen:secret-inject:` namespace.
- Style: Follow `tests/07-openbao.bats` structure — load helpers first, constants at top, setup/teardown bracket the tests.

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|-------------|-------------|----------|
| Integration | Consumer cluster `fury-baobank-consumer` exists and is ready | `kind get clusters` includes the consumer cluster |
| Integration | OpenBao reachable from consumer cluster | HTTP health check via `curl` or `wget` from a consumer pod |
| Integration | AppRole login succeeds cross-cluster | `vault write auth/approle/login` from consumer context returns a token |
| Integration | vault-env injection works | App pod's init container exits 0, main container runs |
| Integration | App pod has correct env var value | `kubectl exec` on consumer cluster shows `DB_PASSWORD=s3cret` |
| Security | Non-vault SA cannot read approle-credentials Secret | `kubectl auth can-i get secrets --as=system:serviceaccount:<ns>:default` returns "no" |
| Security | AppRole token TTL <= 1h | Token lookup after login shows TTL <= 3600 |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `tests/08-cross-cluster.bats` exists and passes `bash -n` syntax check
- [ ] BATS file loads helpers and follows existing test structure from `07-openbao.bats`
- [ ] Test: consumer cluster is running
- [ ] Test: OpenBao on baobank is reachable from consumer cluster
- [ ] Test: AppRole auth succeeds cross-cluster
- [ ] Test: vault-env init container completes successfully
- [ ] Test: app pod has `DB_PASSWORD=s3cret`
- [ ] Test: non-vault ServiceAccount cannot read approle-credentials Secret
- [ ] Test: AppRole token TTL <= 1h
- [ ] No-TLS risk is documented in BATS file comments
- [ ] Mise task `scen:secret-inject:up` orchestrates full scenario setup
- [ ] Mise task `scen:secret-inject:test` runs the BATS suite
- [ ] Mise task `scen:secret-inject:down` tears down cleanly
- [ ] Scenario does NOT run as part of `mise run all` (main test suite)
- [ ] Main `mise run all` (59 tests) still passes independently

## Context / Contesto

- [ ] `.forgia/fd/FD-004-cross-cluster-secret-injection.md` — verification checklist, planned SDDs
- [ ] `.forgia/fd/FD-004-threat-model.md` — security test requirements (RBAC, TTL, no-TLS)
- [ ] `tests/07-openbao.bats` — reference BATS structure, helper usage, setup/teardown patterns
- [ ] `manifests/plugins/kustomize/openbao-tenant-template/vault-cr-template.yaml` — Vault CR for understanding tenant OpenBao setup

## Constitution Check

- [x] Respects code standards (YAML 2-space indent, shell `set -euo pipefail`, BATS conventions)
- [x] Respects commit conventions (`feat(FD-004): ...`)
- [x] No hardcoded secrets (AppRole creds in K8s Secrets, test values only in test fixtures)
- [x] Tests defined and sufficient

---

## Work Log / Diario di Lavoro

> This section is **mandatory**. Must be filled by the agent or developer during and after execution.

### Agent / Agente

- **Executor**: <!-- openhands | claude-code | manual | name -->
- **Started**: <!-- timestamp -->
- **Completed**: <!-- timestamp -->
- **Duration / Durata**: <!-- total time -->

### Decisions / Decisioni

1. <!-- decision 1: what and why -->

### Output

- **Commit(s)**: <!-- hash -->
- **PR**: <!-- link -->
- **Files created/modified**:
  - `tests/08-cross-cluster.bats`
  - `mise.toml` (scen:secret-inject tasks)

### Retrospective / Retrospettiva

- **What worked / Cosa ha funzionato**:
- **What didn't / Cosa non ha funzionato**:
- **Suggestions for future FDs / Suggerimenti per FD futuri**:
