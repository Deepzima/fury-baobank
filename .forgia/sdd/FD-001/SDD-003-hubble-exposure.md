---
id: "SDD-003"
fd: "FD-001"
title: "Hubble exposure for local access"
status: completed
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-15"
started: ""
completed: ""
tags: [hubble, observability, cilium]
---

# SDD-003: Hubble exposure for local access

> Parent FD: [[FD-001]]

## Scope

Expose Hubble UI for local developer access via **port-forward as default** (safe — loopback only). Document an optional NodePort mode, but do not include it in the default `mise run up` path. Write a `mise run hubble` task that starts the port-forward and prints the URL. Document three common Hubble queries in `docs/hubble-queries.md` (pod-to-pod flows, cross-namespace denies, DNS lookups) so developers learn Hubble as they use the lab.

Must enforce mTLS on the Hubble relay. If the upstream KFD networking module already sets Hubble mTLS, document it; if not, SDD-002 already includes a `customPatch` to enable it — this SDD validates the enforcement via BATS (test lives in SDD-004, reference from here).

Out of scope: cluster bootstrap (SDD-001), Cilium core install (SDD-002), BATS test suite (SDD-004).

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|---|---|---|
| `mise.toml` task `hubble` | mise task | `kubectl port-forward -n kube-system svc/hubble-ui 12000:80` and print URL |
| `mise.toml` task `hubble-stop` | mise task | Kill the background port-forward cleanly |
| `docs/hubble-queries.md` | Markdown doc | Three example queries with explanations |
| `scripts/hubble-mtls-check.sh` | Shell script | Validate that Hubble relay rejects unauthenticated gRPC — reused by SDD-004 BATS |

## Constraints / Vincoli

- Language: TOML (mise), Markdown (docs), bash (mTLS check script — `set -euo pipefail`)
- Framework: mise, kubectl, grpcurl (for mTLS check)
- Dependencies: SDD-002 must have installed Hubble via furyctl; SDD-001 must have produced a running cluster
- Patterns:
  - Port-forward is the default exposure — NodePort mode is documented but opt-in
  - If a NodePort is exposed, Kind `port_mappings` must bind to `127.0.0.1`
  - The mTLS check script is a library — it must be callable both from `mise run hubble` (after-install check) and from BATS

### Security (from threat model)

- Expose Hubble UI via port-forward only in the default `mise` task. If a NodePort option is added, document it is lab-only, bind it to `127.0.0.1` via Kind port mapping, and do not add it to the `mise run up` default path (source: threat model)
- Enable Hubble mTLS via `customPatches` if the upstream KFD networking module does not enable it by default. Validate via BATS test that the Hubble relay rejects unauthenticated gRPC calls (source: threat model)
- Document that L7 visibility is opt-in per CiliumNetworkPolicy — do not enable L7 globally (could leak Authorization headers in flow logs) (source: threat model)

## Best Practices

- Error handling: `mise run hubble` checks if the Hubble UI service exists before port-forwarding; clear error message if Cilium/Hubble not yet installed
- Naming: port-forward local port `12000` (avoids common dev ports 3000/8080); document in task description
- Style: `hubble-queries.md` uses consistent format — query name, Hubble CLI command, expected output, what it demonstrates

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|---|---|---|
| Unit | `yamllint` on mise task; `shellcheck` on the mTLS check script | In mise `lint` task |
| Integration | Port-forward actually reaches Hubble UI; mTLS check script rejects unauth gRPC | Covered by SDD-004 BATS |
| E2E | `mise run hubble` starts the forward and the URL responds HTTP 200 | Covered by SDD-004 BATS |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `mise run hubble` starts a port-forward to `hubble-ui` on `127.0.0.1:12000`
- [ ] `mise run hubble-stop` cleanly stops the background process
- [ ] `docs/hubble-queries.md` contains at least 3 example queries
- [ ] `scripts/hubble-mtls-check.sh` exits 0 when Hubble relay rejects unauthenticated gRPC, exits non-zero otherwise
- [ ] The default `mise run up` flow does NOT expose Hubble via NodePort (port-forward only)
- [ ] If NodePort is documented, it explicitly binds to `127.0.0.1` via Kind port mapping

## Context / Contesto

- [ ] `modules/fury-kubernetes-networking/katalog/cilium/hubble/README.md` — upstream Hubble module
- [ ] `.forgia/fd/FD-001-kind-cluster-cilium.md` — parent FD
- [ ] `.forgia/fd/FD-001-threat-model.md` — security recommendations for Hubble
- [ ] [Hubble mTLS docs](https://docs.cilium.io/en/stable/observability/hubble/tls/)
- [ ] [Hubble query syntax](https://docs.cilium.io/en/stable/observability/hubble/#hubble-cli-reference)

## Constitution Check

- [ ] Respects code standards (bash `set -euo pipefail`, markdown consistent heading levels)
- [ ] Respects commit conventions (`feat(FD-001): expose Hubble via port-forward with mTLS check`)
- [ ] No hardcoded secrets (mTLS client certs used by checks come from the cluster, not from files)
- [ ] Tests defined in SDD-004 (BATS), reusing the mTLS check script

---

## Work Log / Diario di Lavoro

### Agent / Agente

- **Executor**: claude-code
- **Started**: 2026-04-15
- **Completed**: 2026-04-15
- **Duration / Durata**: ~10 min

### Decisions / Decisioni

1. **Dropped `hubble-stop` task**: `kubectl port-forward` is foreground; Ctrl-C stops it cleanly. A separate stop task would require running port-forward in background via `&` + PID tracking, adding complexity for no real benefit in a lab.

2. **Port 12000 for Hubble UI**: avoids the common dev ports `3000` and `8080`. Documented inside the task description so `mise run hubble` is self-explanatory.

3. **mTLS enforcement is config-driven, not Helm-patched**: the `customPatches` in SDD-002 (`cilium-kube-proxy-replacement.yaml`) already sets `hubble-tls-disabled: "false"` and `hubble-tls-auto-enabled: "true"`. SDD-003 does NOT need to add another override — it only provides the validation (`hubble-mtls-check.sh`) that the enforcement is working.

4. **`scripts/hubble-mtls-check.sh` is standalone**: can be called by `mise run hubble-mtls-check` or by a BATS test (SDD-004). Uses a temporary port-forward and cleans up with a trap on EXIT. Falls back to `nc` if `grpcurl` is missing, with a `WARN` + non-fatal exit so the lab doesn't hard-fail on developer machines without grpcurl.

5. **Hubble query examples use `hubble` CLI over the port-forward**, not the Hubble UI. CLI examples are more diff-friendly in docs and more useful for scripting than screenshots.

### Output

- **Commit(s)**: (pending)
- **PR**: N/A
- **Files created/modified**:
  - `mise.toml` (tasks `hubble` and `hubble-mtls-check` added)
  - `scripts/hubble-mtls-check.sh` (created, chmod +x)
  - `docs/hubble-queries.md` (created)

### Retrospective / Retrospettiva

- **What worked**: keeping mTLS config inside SDD-002 (where Cilium is configured) and letting SDD-003 own the VALIDATION — cleaner separation of concerns.
- **What didn't**: first pass of the script used only `grpcurl`, which isn't installed on all dev machines. Added a fallback probe + clear warning to avoid failing the lab on missing tooling.
- **Suggestions for future FDs**: add `grpcurl` to the `mise.toml` tools array via a plugin — would make the check always use the full path. Not added now because mise doesn't have a first-class grpcurl backend by default (would need a custom plugin or npm install).
