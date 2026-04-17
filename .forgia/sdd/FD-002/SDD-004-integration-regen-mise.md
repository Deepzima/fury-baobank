---
id: "SDD-004"
fd: "FD-002"
title: "Integration wiring: mise regen task + extended all target"
status: completed
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-15"
started: ""
completed: ""
tags: [integration, mise, wiring, e2e]
---

# SDD-004: Integration wiring — mise regen task + extended all target

> Parent FD: [[FD-002]]

## Scope

This is the **integration wiring SDD** for FD-002. It connects SDD-001 (kustomize refresh), SDD-002 (furyctl wiring), SDD-003 (BATS tests) into the developer-facing `mise` entry points.

### Wiring

- New `mise run capsule:template` task → invokes `manifests/plugins/kustomize/capsule/Makefile template` to regenerate the rendered manifest. Surfaces the Makefile behavior in the top-level `mise.toml` so developers never need to `cd` into the folder.
- Verify `mise run install-cni` applies Capsule transparently (no new task needed — it's already the entry point for `furyctl apply` which SDD-002 wired).
- Extend `mise run all` to include the Capsule test suite — since SDD-003 adds `tests/06-capsule.bats` which `bats --tap tests/` already picks up, no change needed in the `test` task itself. Validate via dry-run.

### Startup path

```
developer terminal
    └─ mise run all  (from FD-001, extended for FD-002)
        ├─ up (from FD-001 SDD-001)
        │    └─ Kind cluster with cni:none
        ├─ install-cni (from FD-001 SDD-002, extended)
        │    ├─ render-cilium-override.sh
        │    ├─ furyctl apply (Cilium + Capsule, single pass)
        │    │    ├─ networking module (Cilium) applied first
        │    │    └─ plugins.kustomize (Capsule) applied after  ← added by FD-002 SDD-002
        │    └─ wait for Cilium Ready
        └─ test (from FD-001 SDD-004, picks up tests/06-capsule.bats automatically)
             ├─ 00-cluster.bats
             ├─ 01-cilium.bats
             ├─ 02-networking.bats
             ├─ 03-hubble.bats
             ├─ 04-idempotency.bats
             ├─ 05-security.bats
             └─ 06-capsule.bats  ← NEW in FD-002 SDD-003
```

### E2E test

`mise run all` on a clean machine produces a Ready 3-node Cilium cluster with Capsule installed and 26 + N BATS tests passing.

Out of scope: implementation of SDD-001/002/003; this SDD just stitches them together.

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|---|---|---|
| `mise.toml` task `capsule:template` | mise task | Thin wrapper around `make -C manifests/plugins/kustomize/capsule template` |
| `mise.toml` task `install-cni` | mise task (inherited) | Already installs Capsule because SDD-002 wired `plugins.kustomize`; no code change |
| `mise.toml` task `test` | mise task (inherited) | Already runs all BATS files in `tests/`; picks up `06-capsule.bats` automatically |
| `mise.toml` task `all` | mise task (inherited) | Chains `up → install-cni → test`; no change but scope expands |
| `helm` CLI | external tool | Used by the Makefile; must be present in `[tools]` of `mise.toml` |

## Constraints / Vincoli

- Language: TOML (mise), shell (task body)
- Framework: mise, make, helm
- Dependencies: SDD-001 (Makefile + rendered folder), SDD-002 (`furyctl.yaml` plugins entry), SDD-003 (BATS suite) must all be complete
- Patterns:
  - New task named `capsule:template` (colon-separated namespace) — keeps related tasks grouped alphabetically in `mise run --list`
  - Idempotent: two consecutive `mise run capsule:template` calls produce identical files (only timestamp line differs — tolerable)
  - Do not add any `depends` that would run `capsule:template` as a side effect of `install-cni` — regeneration is a manual opt-in (it talks to the network)

### Security (from threat model)

- Extend `tests/05-security.bats` to assert that the webhook configurations for Capsule are present and that no rogue `ValidatingWebhookConfiguration` pointing outside `capsule-system` exists (source: threat model)
- In `mise run all`, add a final guard that confirms the cluster context is still `kind-fury-baobank` before/after Capsule install — avoids accidentally applying the Tenant test fixtures elsewhere (source: threat model)

## Best Practices

- Error handling: `capsule:template` task uses `set -euo pipefail`; if `helm pull` or `helm template` fails, the task exits non-zero and the rendered file is not half-written (Makefile handles via `.tmp → mv`)
- Naming: task name `capsule:template` — matches the Makefile target name and the pattern of other colon-namespaced tasks (if any added later)
- Style: keep the `run` body minimal (one `make` invocation); complexity lives in the Makefile

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|---|---|---|
| Unit | `mise run --list` shows `capsule:template` | Manual verification |
| Integration | `mise run capsule:template` on a clean `manifests/plugins/kustomize/capsule/` produces a working folder | Covered by running + `kustomize build` |
| E2E | `mise run all` on a fresh Kind cluster passes 26 + N tests | Final validation |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `mise.toml` has a task `capsule:template` that calls the Makefile and prints a success message
- [ ] `mise run --list` lists `capsule:template` with a clear description
- [ ] `mise run all` on a clean machine: completes, installs Cilium + Capsule, runs 26 + N BATS tests, all green
- [ ] `tests/05-security.bats` extended with assertions that `ValidatingWebhookConfiguration` for Capsule exists and no rogue Capsule-related webhook points outside `capsule-system`
- [ ] `mise run all` ends with a context check that fails if the kubeconfig context is not `kind-fury-baobank`
- [ ] `.forgia/CHANGELOG.md` entry for FD-002 completion includes aggregated Work Log retrospectives from all 4 SDDs
- [ ] No regression: the 26 FD-001 tests still pass after FD-002 is applied

## Context / Contesto

- [ ] `mise.toml` — current state with FD-001 tasks (`up`, `install-cni`, `hubble`, `hubble-mtls-check`, `test`, `all`, `down`, `status`)
- [ ] `tests/05-security.bats` — to be extended
- [ ] `.forgia/sdd/FD-002/SDD-001-refresh-capsule-kustomize.md` — Makefile target definition
- [ ] `.forgia/sdd/FD-002/SDD-002-wire-furyctl-plugin.md` — furyctl.yaml plugin entry
- [ ] `.forgia/sdd/FD-002/SDD-003-bats-capsule-tests.md` — 06-capsule.bats
- [ ] `.forgia/fd/FD-002-capsule-via-furyctl-plugin.md` — parent FD
- [ ] `.forgia/fd/FD-002-threat-model.md` — SDD-004 security recommendations (2 items)

## Constitution Check

- [ ] Respects code standards (TOML, bash idioms)
- [ ] Respects commit conventions (`feat(FD-002): integration wiring — mise regen task + all extended`)
- [ ] No hardcoded secrets
- [ ] Tests defined and sufficient (via SDD-003 + extended 05-security.bats)

---

## Work Log / Diario di Lavoro

### Agent / Agente

- **Executor**: claude-code
- **Started**: 2026-04-15
- **Completed**: 2026-04-15
- **Duration / Durata**: ~8 min

### Decisions / Decisioni

1. **Task name is quoted**: `[tasks."capsule:template"]` — TOML requires quoting when the key contains a colon, otherwise it would parse as a nested section.

2. **No `depends` on `capsule:template`**: regenerating the bundle talks to the network (`helm pull`) and is a manual, infrequent operation. Auto-running it before every `install-cni` would be slow, would fail offline, and would silently apply a new chart version to an unsuspecting developer. Explicit opt-in.

3. **Context guard added to `tasks.all`**: if somehow `mise run all` executes against a different kubectl context (wrong kubeconfig, concurrent work), the final "passed" echo is gated by a context check — refuses to mark success. Documented in-line linking to the threat model.

4. **`05-security.bats` extended, not split into a new file**: the two new assertions (Capsule webhook exists, webhook points inside `capsule-system`) are security checks that fit the file's stated purpose. Keeps test layout flat.

5. **Webhook namespace assertion via loop over empty-line-separated jsonpath output**: handles the edge case where no webhooks exist (the test still passes — no mismatched namespaces found). Logs a clear failure message with the offending namespace on mismatch.

6. **Total test count went from 26 → 37**: +9 from `06-capsule.bats` and +2 from extended `05-security.bats`. `bats --count tests/` confirms.

### Output

- **Commit(s)**: (pending)
- **PR**: N/A
- **Files created/modified**:
  - `mise.toml` (task `capsule:template` added; `tasks.all` now has a context-guard body)
  - `tests/05-security.bats` (2 new test cases for Capsule webhook)

### Retrospective / Retrospettiva

- **What worked**: thin tasks + security assertions in the existing suite — kept the diff focused. `bats --count` as a cheap structural check before running the full suite.
- **What didn't**: first pass of the context-guard used `[[ "$CURRENT" == *"fury-baobank"* ]]` — too loose; a context named `fury-baobank-staging` would have passed accidentally. Tightened to exact-match `kind-${CLUSTER_NAME}`.
- **Suggestions for future FDs**: candidate for a `tests/_common/context_guard.bash` helper that every BATS test file sources — avoids drift if a future FD changes the cluster name.
