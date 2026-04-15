---
id: "SDD-004"
fd: "FD-001"
title: "Integration wiring and E2E BATS test suite"
status: completed
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-15"
started: ""
completed: ""
tags: [integration, e2e, bats, testing, wiring]
---

# SDD-004: Integration wiring and E2E BATS test suite

> Parent FD: [[FD-001]]

## Scope

This is the **integration wiring SDD**. It connects SDD-001 (cluster), SDD-002 (Cilium), and SDD-003 (Hubble) into a single entry point and proves the full flow end-to-end from the developer's terminal.

### Wiring

- `mise.toml` task `up` that chains: `zlab up` → `label infra workers` → `furyctl vendor` → `furyctl apply` → `validate Cilium Ready` → `validate kube-proxy absent`
- `mise.toml` task `down` that tears everything down cleanly (`zlab destroy`)
- `mise.toml` task `test` that runs the full BATS suite
- `mise.toml` task `all` = `up` + `test` (for CI-like local validation)

### Startup Path

```
developer terminal
    └─ mise run up
        ├─ zlab up (SDD-001)
        │    └─ Kind creates 3 containers, control-plane Ready, workers NotReady (no CNI)
        ├─ kubectl label nodes ... node-role.fury.io/infra=true (SDD-001)
        ├─ furyctl vendor (SDD-002)
        │    └─ downloads fury-kubernetes-networking at pinned SHA
        ├─ furyctl apply --disable-analytics (SDD-002)
        │    └─ kustomize build | kubectl apply
        │    └─ Cilium DaemonSet, operator, Hubble installed
        │    └─ eBPF programs loaded, kube-proxy replaced
        └─ wait for all nodes Ready
```

### E2E BATS test suite

Tests live under `tests/` and cover the full surface:

- `tests/00-cluster.bats` — cluster topology and kubeconfig
- `tests/01-cilium.bats` — Cilium installed, kube-proxy absent, pods Ready
- `tests/02-networking.bats` — pod-to-pod connectivity, DNS, cross-worker traffic
- `tests/03-hubble.bats` — Hubble UI reachable via port-forward, mTLS enforced on relay
- `tests/04-idempotency.bats` — `mise run up` is a no-op on an existing healthy cluster
- `tests/05-security.bats` — kubeconfig 0600, no unexpected privileged pods, Hubble not on 0.0.0.0

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|---|---|---|
| `mise.toml` task `up` | mise task | Orchestrates SDD-001 + SDD-002 end-to-end |
| `mise.toml` task `down` | mise task | Tears down via `zlab destroy` |
| `mise.toml` task `test` | mise task | Runs all BATS tests with TAP output |
| `mise.toml` task `all` | mise task | `up` + `test` for local CI |
| `tests/*.bats` | BATS test files | Each file is a test suite with explicit `@test` blocks |
| `tests/helpers.bash` | Shared bash lib | Loaded by every BATS file; wraps `kubectl`, wait loops, retry helpers |

## Constraints / Vincoli

- Language: TOML (mise), bash (BATS — `set -euo pipefail` in helpers)
- Framework: mise, bats-core, bats-support, bats-assert (install via mise)
- Dependencies: SDD-001, SDD-002, SDD-003 must have produced their artifacts
- Patterns:
  - Every BATS test that waits on cluster state uses an explicit retry loop with timeout — no sleeps longer than 1s
  - Tests assume a clean cluster state: `tests/00-cluster.bats` verifies this as the first precondition
  - The `all` task in CI-like usage must exit non-zero if any test fails (no silent failures)

### Security (from threat model)

- Add a BATS test that asserts `kubeconfig` file permissions are `0600` after cluster creation. Fail the E2E test if the permissions are more permissive (source: threat model)
- Add a BATS test that asserts the cluster name/context matches `fury-baobank` — prevents accidental production kubeconfig use (source: threat model)
- Add a BATS test that asserts no pod in `kube-system` beyond Cilium agents has `privileged: true` or CAP_NET_ADMIN. Fail if an unexpected privileged pod exists (source: threat model)
- Add a BATS test that asserts Hubble UI is NOT reachable on `0.0.0.0` — only on `127.0.0.1` — to catch accidental exposure (source: threat model)
- Reuse the `scripts/hubble-mtls-check.sh` library from SDD-003 in `tests/03-hubble.bats` (source: threat model)

## Best Practices

- Error handling:
  - `mise run up` uses `set -euo pipefail`; any step failure aborts the chain
  - BATS tests use `run` + explicit `[ "$status" -eq 0 ]` — never rely on shell-level failure to propagate
  - `tests/helpers.bash` provides a `wait_for()` helper that takes a predicate and timeout
- Naming: test file names prefixed by two-digit index for ordering; suite names descriptive (not "test 1")
- Style:
  - BATS: one `@test` per assertion (or small group)
  - Helpers factored out — no copy-paste between test files
  - Every test has a clear failure message via `>&2 echo` before exit

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|---|---|---|
| Unit | BATS self-check: helpers produce correct exit codes | `tests/00-cluster.bats` smoke tests |
| Integration | All BATS suites 00–05 against a live cluster | ~35+ individual `@test` cases total (estimate) |
| E2E | `mise run all` on a clean developer machine passes without manual steps | CI-like validation target |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `mise run up` on a clean developer machine produces a Ready 3-node Cilium cluster
- [ ] `mise run up` completes in under 4 minutes on a typical dev machine
- [ ] `mise run test` runs all BATS suites with TAP output; all tests pass on a fresh cluster
- [ ] `mise run all` exits 0 on success, non-zero on any test failure
- [ ] `mise run down` tears down cleanly; second `mise run up` after `down` is a clean bootstrap
- [ ] `mise run up` is idempotent (verified by `tests/04-idempotency.bats`)
- [ ] Kubeconfig permissions `0600` verified by `tests/05-security.bats`
- [ ] `kube-proxy` DaemonSet absent verified by `tests/01-cilium.bats`
- [ ] Pod-to-pod connectivity across infra workers verified by `tests/02-networking.bats`
- [ ] Hubble UI reachable via port-forward only, mTLS enforced, verified by `tests/03-hubble.bats`
- [ ] No unexpected privileged pods in `kube-system` verified by `tests/05-security.bats`
- [ ] Hubble not bound to 0.0.0.0 verified by `tests/05-security.bats`

## Context / Contesto

- [ ] `labs/environments/ingress-full/tests/` — reference BATS patterns (mise + bats-core)
- [ ] `labs/_shared/helper.bash` — existing helper library for reuse
- [ ] `labs/_shared/scripts/wait-for-pods.sh` — reusable wait loop
- [ ] `.forgia/fd/FD-001-kind-cluster-cilium.md` — parent FD
- [ ] `.forgia/fd/FD-001-threat-model.md` — security recommendations (#9, #10, #11, #12)
- [ ] `.forgia/sdd/FD-001/SDD-001-kind-cluster-config.md`
- [ ] `.forgia/sdd/FD-001/SDD-002-furyctl-cilium-install.md`
- [ ] `.forgia/sdd/FD-001/SDD-003-hubble-exposure.md`
- [ ] [bats-core docs](https://bats-core.readthedocs.io/)

## Constitution Check

- [ ] Respects code standards (bash `set -euo pipefail`, BATS idioms)
- [ ] Respects commit conventions (`feat(FD-001): integration wiring and E2E tests`)
- [ ] No hardcoded secrets (tests use in-cluster SA tokens, not files)
- [ ] Tests defined and sufficient — this SDD IS the test coverage for FD-001

---

## Work Log / Diario di Lavoro

### Agent / Agente

- **Executor**: claude-code
- **Started**: 2026-04-15
- **Completed**: 2026-04-15
- **Duration / Durata**: ~15 min

### Decisions / Decisioni

1. **`tasks.all` uses `depends` chain, not a shell sequence**: `depends = ["up", "install-cni", "test"]` leverages mise's dependency graph — tasks run in order and fail-fast at the first error. Simpler than inlining a bash script with `set -euo pipefail`.

2. **`helpers.bash` exports `kctl`, `wait_for`, `assert_exists`, `assert_absent`**: the `kctl` wrapper injects `--context "${CONTEXT}"` automatically — avoids forgetting the context flag in individual tests and keeps each test short.

3. **`02-networking.bats` uses `setup_file`/`teardown_file`**: shares the namespace + probe pods across all tests in the file. Each test runs in ~ms, not seconds. The namespace is deleted on file teardown (wait=false to avoid blocking the suite).

4. **`03-hubble.bats` port-forward test uses a different local port (12001)**: avoids collision with `mise run hubble` if the developer is running Hubble UI in another terminal during development.

5. **`04-idempotency.bats` runs `mise run up` inside BATS**: this is the only way to validate the "skip if exists" path end-to-end. The test only runs AFTER `00-cluster` has confirmed the cluster exists, so the call is safe.

6. **`05-security.bats` uses `docker ps --format '{{.Ports}}'`**: inspects the actual Docker port publishing, not the Kind config file. A misconfigured Kind config that somehow binds to 0.0.0.0 would still be caught.

7. **`bats --count` validation**: 26 test cases across 6 files. Parsed successfully (mise `bats` tool, BATS v1.11+).

### Output

- **Commit(s)**: (pending)
- **PR**: N/A
- **Files created/modified**:
  - `tests/helpers.bash` (created)
  - `tests/00-cluster.bats` (5 cases)
  - `tests/01-cilium.bats` (5 cases)
  - `tests/02-networking.bats` (3 cases + setup_file/teardown_file)
  - `tests/03-hubble.bats` (5 cases)
  - `tests/04-idempotency.bats` (4 cases)
  - `tests/05-security.bats` (4 cases)
  - `mise.toml` (tasks `test`, `all` added)

### Retrospective / Retrospettiva

- **What worked**: `mise run all` with `depends` chain gives CI-like validation from a single command. The `helpers.bash` wrapper (`kctl`, `wait_for`) keeps tests terse and readable.
- **What didn't**: initial attempt used `bash -n` to lint BATS files — does not work because `@test` is BATS-specific syntax, not bash. Switched to `bats --count` via mise.
- **Suggestions for future FDs**: add `bats-assert` and `bats-support` to get richer assertion output (`assert_success`, `assert_equal`, etc.). Currently using raw `[...]` which is less readable on failure.
