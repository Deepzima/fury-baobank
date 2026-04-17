---
id: "SDD-005"
fd: "FD-003"
title: "Integration wiring: furyctl plugins + mise targets + E2E"
status: assigned
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-17"
started: ""
completed: ""
tags: [integration, mise, furyctl, wiring, e2e]
---

# SDD-005: Integration wiring — furyctl plugins + mise targets + E2E

> Parent FD: [[FD-003]]

## Scope

This is the **integration wiring SDD** for FD-003. It connects SDD-001 (operator plugin), SDD-002 (webhook plugin), SDD-003 (Vault CR fixtures), and SDD-004 (BATS tests) into the developer-facing `mise` and `furyctl` entry points.

### Wiring

1. **`furyctl.yaml`**: add 2 new `plugins.kustomize` entries (operator + webhook). kapp ordering: operator before webhook (operator must register CRDs first).
2. **`mise.toml`**: add `bank-vaults:template` task (regenerates operator + webhook bundles). Verify `install-cni` applies operator + webhook transparently. Verify `test` picks up `tests/07-openbao.bats` automatically.
3. **`tests/07-openbao.bats` setup_file**: provisions 2 Capsule Tenants + 2 Vault CRs as part of the test setup. This is the tenant onboarding flow (creates tenants, applies Vault CRs, waits for OpenBao Ready).
4. **`tests/05-security.bats`**: extend with Bank-Vaults webhook assertions (service namespace, no rogue webhook) — same pattern as FD-002 Capsule webhook checks.
5. **Context guard in `mise run all`**: same pattern as FD-002 — verify kubectl context = `kind-fury-baobank` before marking validation passed.

### Startup path

```
developer terminal
    └─ mise run all
        ├─ up (FD-001 SDD-001)
        │    └─ Kind cluster with cni:none
        ├─ install-cni (FD-001 SDD-002, extended)
        │    ├─ render-cilium-override.sh
        │    ├─ furyctl apply (single pass):
        │    │    ├─ networking module (Cilium)
        │    │    ├─ plugins.kustomize: capsule (FD-002)
        │    │    ├─ plugins.kustomize: bank-vaults-operator (FD-003)  ← NEW
        │    │    └─ plugins.kustomize: bank-vaults-webhook (FD-003)   ← NEW
        │    └─ wait for Cilium Ready
        └─ test (picks up 07-openbao.bats automatically)
             ├─ 00-cluster.bats (5)
             ├─ 01-cilium.bats (5)
             ├─ 02-networking.bats (3)
             ├─ 03-hubble.bats (5)
             ├─ 04-idempotency.bats (4)
             ├─ 05-security.bats (6 + 2 new = 8)
             ├─ 06-capsule.bats (10)
             └─ 07-openbao.bats (~22)                                  ← NEW
```

### E2E test

`mise run all` on a clean machine produces a Ready 3-node Cilium cluster with Capsule + Bank-Vaults operator + webhook installed, 2 test tenants each with a dedicated OpenBao instance, and 38 + 22 = ~60 BATS tests passing.

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|---|---|---|
| `furyctl.yaml` (`plugins.kustomize`) | furyctl config | 2 new entries: bank-vaults-operator, bank-vaults-webhook |
| `mise.toml` task `bank-vaults:template` | mise task | Thin wrapper around Makefiles in both plugin folders |
| `mise.toml` task `install-cni` | mise task (inherited) | Already calls `furyctl apply` — new plugins picked up automatically |
| `mise.toml` task `test` | mise task (inherited) | `bats --tap tests/` picks up `07-openbao.bats` automatically |
| `mise.toml` task `all` | mise task (inherited) | Chains up → install-cni → test → context guard |
| `tests/05-security.bats` | BATS (extended) | 2 new assertions for Bank-Vaults webhook |

## Constraints / Vincoli

- Language: TOML (mise), YAML (furyctl), shell (task body)
- Framework: mise, furyctl, kapp
- Dependencies: SDD-001, SDD-002, SDD-003, SDD-004 must all be complete
- Patterns:
  - `bank-vaults:template` task named with colon-separator (same as `capsule:template`)
  - No `depends` that auto-runs `bank-vaults:template` before `install-cni` (manual, network operation)
  - kapp ordering: operator plugin must apply before webhook plugin (CRDs must exist before webhook references them)
  - Vault CRs are NOT in `furyctl.yaml` plugins — they're applied by the test `setup_file` (per-tenant, ephemeral)

### Security (from threat model)

- Verify kapp ordering: operator before webhook — if webhook applies before CRDs exist, it fails and blocks pod creation cluster-wide (source: threat model)
- Context guard in `mise run all`: refuse to mark success if kubectl context != `kind-fury-baobank` (source: threat model)
- Verify total test count = 38 + ~22 = ~60 on fresh cluster (source: threat model)

## Best Practices

- Error handling: `bank-vaults:template` task uses `set -euo pipefail`
- Naming: `bank-vaults:template` (matches `capsule:template` pattern)
- Style: keep task body minimal — complexity in Makefiles

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|---|---|---|
| Unit | `mise run --list` shows `bank-vaults:template` | Manual verification |
| Integration | `furyctl apply` installs operator + webhook + Capsule + Cilium in single pass | Runtime |
| E2E | `mise run all` on fresh cluster: ~60 tests all green | Final validation |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `furyctl.yaml` has 2 new `plugins.kustomize` entries (operator + webhook)
- [ ] kapp ordering ensures operator applies before webhook
- [ ] `mise.toml` has task `bank-vaults:template` with clear description
- [ ] `mise run --list` shows `bank-vaults:template`
- [ ] `tests/05-security.bats` extended with 2 Bank-Vaults webhook assertions
- [ ] `mise run all` on fresh cluster: all ~60 BATS tests pass
- [ ] No regression: 38 FD-001/FD-002 tests still pass
- [ ] Context guard in `all` task still works
- [ ] `.forgia/CHANGELOG.md` entry for FD-003 includes aggregated Work Log retrospectives

## Context / Contesto

- [ ] `furyctl.yaml` — current state with Cilium + Capsule plugins
- [ ] `mise.toml` — current state with `capsule:template`, `all`, `test` tasks
- [ ] `tests/05-security.bats` — to be extended with Bank-Vaults webhook checks
- [ ] `.forgia/sdd/FD-002/SDD-005-integration-regen-mise.md` — reference integration wiring SDD from FD-002
- [ ] `.forgia/fd/FD-003-openbao-bank-vaults-operator.md` — parent FD
- [ ] `.forgia/fd/FD-003-threat-model.md` — security recommendations

## Constitution Check

- [ ] Respects code standards (TOML, bash idioms)
- [ ] Respects commit conventions (`feat(FD-003): integration wiring — furyctl + mise + E2E`)
- [ ] No hardcoded secrets
- [ ] Tests defined and sufficient (via SDD-004 + extended 05-security.bats)

---

## Work Log / Diario di Lavoro

### Agent / Agente

- **Executor**: <!-- openhands | claude-code | manual -->
- **Started**: <!-- timestamp -->
- **Completed**: <!-- timestamp -->
- **Duration / Durata**: <!-- total time -->

### Decisions / Decisioni

1. <!-- decision 1 -->

### Output

- **Commit(s)**: <!-- hash -->
- **PR**: <!-- link -->
- **Files created/modified**:
  - `path/to/file`

### Retrospective / Retrospettiva

- **What worked**:
- **What didn't**:
- **Suggestions for future FDs**:
