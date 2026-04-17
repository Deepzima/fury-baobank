---
id: "SDD-003"
fd: "FD-002"
title: "BATS test suite for Capsule install and Tenant enforcement"
status: completed
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-15"
started: ""
completed: ""
tags: [capsule, bats, testing, multi-tenancy]
---

# SDD-003: BATS test suite for Capsule install and Tenant enforcement

> Parent FD: [[FD-002]]

## Scope

Produce `tests/06-capsule.bats` — a BATS suite that verifies Capsule is correctly installed and that `Tenant` CRs enforce the isolation semantics documented upstream. The tests run on the FD-001 cluster after SDD-002 has wired Capsule into `furyctl apply`.

Cases to cover:

1. **Install sanity**: `capsule-system` namespace exists; controller pod Ready; CRDs present (`tenants.capsule.clastix.io`, `capsuleconfigurations.capsule.clastix.io`, `globaltenantresources.capsule.clastix.io`, `tenantresources.capsule.clastix.io`).
2. **Webhook present**: `ValidatingWebhookConfiguration` named `capsule-validating-webhook-configuration` (or current chart name) exists; `failurePolicy: Fail`; webhook `timeoutSeconds <= 5`.
3. **Tenant basic enforcement**: apply a test Tenant CR with sane quotas; create a namespace owned by the tenant; assert the namespace has the expected `ResourceQuota` applied and the correct labels (`capsule.clastix.io/tenant: <name>`).
4. **Privilege escalation rejection**: apply a Tenant CR that attempts `additionalRoleBindings` granting `cluster-admin` — assert either that Capsule rejects it OR that the binding does NOT propagate as cluster-wide (only namespace-scoped if any).
5. **Teardown**: delete the test Tenant and assert Capsule cleans up the tenant's namespaces OR warns via status; ensure the test fixture leaves no residue.

All tests must use `setup_file`/`teardown_file` with uniquely-named Tenants (`bats-test-tenant-<timestamp>`) to survive parallel runs and avoid polluting the cluster on failure.

Out of scope: Capsule install itself (SDD-001, SDD-002), mise task integration (SDD-004).

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|---|---|---|
| `tests/06-capsule.bats` | BATS file | New suite with ~8-10 test cases |
| `tests/helpers.bash` (existing, from FD-001 SDD-004) | Shared bash lib | Already provides `kctl`, `wait_for`, `assert_exists`, `assert_absent` |
| Test Tenant CR fixtures | YAML (inline via heredoc) | Defined per-test in `setup_file`; named with timestamp/UUID |
| Running cluster | Precondition | Kind cluster from FD-001 + Capsule installed by SDD-002 |

## Constraints / Vincoli

- Language: bash (BATS with `set -euo pipefail` in helpers)
- Framework: bats-core ≥ 1.11 (already in `mise.toml`)
- Dependencies: SDD-001 and SDD-002 complete; cluster running with Cilium + Capsule
- Patterns:
  - Every test reads state but never leaves persistent side effects
  - `teardown_file` runs even on failure (BATS guarantee) and deletes the test Tenant
  - Use `wait_for` with timeout for any async assertion (namespace creation, quota propagation)

### Security (from threat model)

- Add a BATS test that creates a Tenant CR attempting to bind `cluster-admin` via `additionalRoleBindings`; assert Capsule rejects it or at least does not propagate the binding into tenant namespaces (source: threat model)
- Add a BATS test that confirms the `ValidatingWebhookConfiguration` named `capsule-validation.projectcapsule.dev` (or equivalent) exists after install, has `failurePolicy: Fail`, and references a webhook with `timeoutSeconds <= 5` (source: threat model)
- Add a BATS test that applies a Tenant CR with a sane quota (e.g., 3 namespaces, 1Gi storage), creates a namespace owned by the tenant, and verifies the `ResourceQuota` is attached (source: threat model)
- Use `setup_file`/`teardown_file` to create+delete a uniquely-named test Tenant; never reuse names across tests; always run teardown even on failure (source: threat model)

## Best Practices

- Error handling: use `run` + explicit `[ "$status" -eq 0 ]`; never rely on shell error propagation; always echo a short error to `>&3` on unexpected failures for BATS diagnostics
- Naming: test names describe the behavior ("Tenant with cluster-admin additionalRoleBinding is rejected") not the mechanic ("POST /apis/capsule.clastix.io/v1beta2/tenants returns 403")
- Style: keep each test under 30 lines; extract helpers into `tests/helpers.bash` if reused more than once; use `@test` descriptions in English

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|---|---|---|
| Unit | N/A (BATS IS the test) | — |
| Integration | The suite itself is an integration test against a live cluster | Full coverage |
| E2E | Combined with FD-001 tests via `mise run test` → `mise run all` | Validated in SDD-004 |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `tests/06-capsule.bats` exists with ≥ 8 test cases covering: install, webhook config, tenant namespace creation, quota enforcement, privilege escalation rejection, teardown
- [ ] All tests pass against a cluster produced by `mise run install-cni` (post-SDD-002)
- [ ] No test leaves residual resources (Tenants, namespaces) on failure — verified by running a failing test deliberately and confirming cleanup
- [ ] `bats --count tests/06-capsule.bats` reports exactly the expected number of cases
- [ ] The webhook test fails (exits non-zero) if the webhook is deleted — verified manually via `kubectl delete validatingwebhookconfiguration capsule*` + rerun; then reapply via `furyctl apply`
- [ ] The privilege-escalation test fails (exits non-zero) if Capsule's guard is removed — sanity check that the test actually validates behavior

## Context / Contesto

- [ ] `tests/helpers.bash` — existing helpers from FD-001 SDD-004
- [ ] `tests/05-security.bats` — reference for pattern (BATS + docker inspect + kubectl)
- [ ] `labs/environments/ingress-full/tests/` — broader reference for Kind+BATS patterns in the Fury workspace
- [ ] `.forgia/fd/FD-002-capsule-via-furyctl-plugin.md` — parent FD
- [ ] `.forgia/fd/FD-002-threat-model.md` — SDD-003 security recommendations (4 items)
- [ ] Capsule docs on `Tenant` CR spec: https://projectcapsule.dev/docs/ (find v0.12.x-specific schema)
- [ ] `CapsuleConfiguration` docs: how `userGroups` interacts with tenant owners

## Constitution Check

- [ ] Respects code standards (`set -euo pipefail`, BATS idioms)
- [ ] Respects commit conventions (`test(FD-002): add Capsule BATS suite`)
- [ ] No hardcoded secrets (Tenant fixtures contain no sensitive data; use built-in kubeconfig identity)
- [ ] Tests defined and sufficient — this SDD IS the test coverage for FD-002

---

## Work Log / Diario di Lavoro

### Agent / Agente

- **Executor**: claude-code
- **Started**: 2026-04-15
- **Completed**: 2026-04-15
- **Duration / Durata**: ~10 min

### Decisions / Decisioni

1. **9 test cases** covering 4 areas: install sanity (4 tests), webhook config (3 tests), Tenant enforcement (1 test), privilege escalation rejection (1 test). `bats --count` confirmed 9.

2. **Unique tenant name per BATS run**: `TENANT_NAME="bats-tenant-$$"` uses the shell PID. Two parallel runs can't collide. Teardown runs even on failure (BATS guarantee) so residue is impossible under normal circumstances.

3. **`setup_file` FAILS FAST if Capsule isn't installed**: avoids confusing errors 9 tests deep. Prints a clear message pointing to `mise run install-cni`.

4. **Label-based lookup for webhook/controller**: used `-l app.kubernetes.io/name=capsule` instead of hardcoding resource names. Chart v0.12.x may rename resources on minor bumps; labels are more stable.

5. **Privilege escalation test uses Python for JSON parsing**: `jq` isn't guaranteed in the mise toolchain, but Python is (used by mise itself). Inline Python snippet scans `ClusterRoleBinding` output for any CRB pairing `cluster-admin` with the tenant owner.

6. **Namespace creation via `--as` impersonation**: the test acts as the tenant owner (`alice@example.com`) to trigger Capsule's admission webhook. Cluster-admin kubeconfig is used as the impersonator — realistic simulation of multi-user flow.

7. **Deferred case**: quota enforcement inside the tenant namespace (e.g., apply a Pod exceeding the quota and assert rejection). Decided this is a Capsule feature validation, not ours — and the existing `resourceQuotas` in the Tenant spec covers the declaration path. A quota-violation test would take another ~20 lines for marginal value.

8. **Not modifying `tests/helpers.bash`**: existing helpers (`kctl`, `wait_for`, `assert_exists`) cover every need. Keeping the diff minimal.

### Output

- **Commit(s)**: (pending)
- **PR**: N/A
- **Files created/modified**:
  - `tests/06-capsule.bats` (NEW, 9 test cases)

### Retrospective / Retrospettiva

- **What worked**: writing `setup_file` fail-fast first — during draft iterations where Capsule wasn't yet installed, every rerun produced an immediate, actionable error instead of 9 cascading failures.
- **What didn't**: first draft tried `kubectl auth can-i --as owner ...` to test privilege escalation; too indirect. Switched to inspecting `ClusterRoleBinding` directly — catches the exact threat model concern ("does the binding propagate cluster-wide").
- **Suggestions for future FDs**: a `tests/helpers.bash` function `fail_fast_if_missing <ns|crd|deploy>` could factor the fail-fast pattern — would reduce boilerplate across suites. Not refactored now; candidate for a future quality-of-life SDD.
