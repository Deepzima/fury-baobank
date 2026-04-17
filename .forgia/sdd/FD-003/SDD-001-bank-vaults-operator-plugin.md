---
id: "SDD-001"
fd: "FD-003"
title: "Bank-Vaults operator kustomize plugin"
status: assigned
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-17"
started: ""
completed: ""
tags: [bank-vaults, operator, kustomize, helm]
---

# SDD-001: Bank-Vaults operator kustomize plugin

> Parent FD: [[FD-003]]

## Scope

Render the Bank-Vaults vault-operator Helm chart (v1.23.x) into a kustomize-buildable bundle at `manifests/plugins/kustomize/bank-vaults-operator/`. The operator deploys in `bank-vaults-system` namespace and watches ALL namespaces for `Vault` CRs (per-tenant architecture — one `Vault` CR per tenant namespace produces one dedicated OpenBao StatefulSet).

### Deliverables

- `manifests/plugins/kustomize/bank-vaults-operator/Makefile` — chart pull + `helm template` (same pattern as Capsule SDD-001 from FD-002)
- `manifests/plugins/kustomize/bank-vaults-operator/values.yaml` — resource limits, log level, RBAC config
- `manifests/plugins/kustomize/bank-vaults-operator/kustomization.yaml` — CRDs + rendered output + namespace + patches
- `manifests/plugins/kustomize/bank-vaults-operator/resources/namespace.yaml` — `bank-vaults-system` with PSA labels
- `manifests/plugins/kustomize/bank-vaults-operator/crds/` — Vault CRD from chart
- `manifests/plugins/kustomize/bank-vaults-operator/resources/bank-vaults-operator-from-helm.yaml` — rendered chart output

### NOT in scope

- Webhook (SDD-002), Vault CR (SDD-003), tests (SDD-004), furyctl wiring (SDD-005).

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|---|---|---|
| `Makefile` target `template` | shell (make) | Pulls chart, renders with `helm template`, outputs to `resources/` |
| `values.yaml` | YAML | Operator values: replicas, resources, log level, RBAC scope |
| `kustomization.yaml` | kustomize | Assembles CRDs + namespace + rendered helm + patches |
| `Vault` CRD | K8s CRD | Registered by the operator; consumed by SDD-003 |
| Operator Deployment | K8s Deployment | Runs in `bank-vaults-system`, watches all namespaces |
| Operator ClusterRole | K8s RBAC | Cross-namespace access to Secrets, StatefulSets, Vault CRs |

## Constraints / Vincoli

- Language: YAML, Makefile, shell
- Framework: helm (chart render), kustomize (assembly)
- Dependencies: `helm` CLI, `kustomize` CLI (both in `mise.toml [tools]`)
- Chart: `bank-vaults/vault-operator` v1.23.x from `https://kubernetes-charts.banzaicloud.com`
- Patterns:
  - Same Makefile structure as `manifests/plugins/kustomize/capsule/Makefile` (FD-002)
  - Chart version pinned in Makefile, not floating
  - Rendered output committed to repo (large file, reviewable diffs)
  - Namespace YAML with PSA labels (`baseline` enforce, `restricted` audit/warn)
  - `--include-crds=false` in helm template (CRDs managed separately for kapp ordering)

### Security (from threat model)

- Pin operator image by tag in `values.yaml`. Digest pinning preferred for production but tag acceptable for lab (source: threat model)
- Set operator log level to `info` (not `debug`) — debug logs may contain unseal keys or root tokens across tenant instances (source: threat model)
- Audit the rendered ClusterRole: must NOT have `["*"]` verbs or `["*"]` resources. Document the operator's cross-namespace access as the platform trust root (source: threat model)
- If the chart supports `replicas > 1`, set to 2 for HA. If not, document single-replica risk (source: threat model)

## Best Practices

- Error handling: Makefile uses `.tmp → mv` pattern (no half-written renders on failure)
- Naming: follow the Capsule pattern — `bank-vaults-operator-from-helm.yaml` for rendered output
- Style: provenance header in rendered file (chart name, version, timestamp, regen command)
- Validate with `kustomize build` after rendering — must produce valid K8s manifests

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|---|---|---|
| Unit | `kustomize build manifests/plugins/kustomize/bank-vaults-operator/` succeeds | Structural |
| Integration | Operator Deployment reaches Ready in `bank-vaults-system` | Runtime (via SDD-004) |
| E2E | `mise run all` includes operator readiness check | Via SDD-005 |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `manifests/plugins/kustomize/bank-vaults-operator/` directory exists with Makefile, values.yaml, kustomization.yaml, resources/, crds/
- [ ] `kustomize build` produces valid output with Deployment, ClusterRole, ClusterRoleBinding, ServiceAccount, CRD
- [ ] Operator image is pinned by tag (not `:latest`)
- [ ] ClusterRole does not contain `["*"]` verbs
- [ ] `values.yaml` sets `logLevel: info` and resource requests/limits
- [ ] `namespace.yaml` has PSA labels (baseline enforce, restricted audit/warn)
- [ ] `Makefile template` regenerates the bundle deterministically
- [ ] Vault CRD is in `crds/` directory (separate from rendered chart output)

## Context / Contesto

- [ ] `manifests/plugins/kustomize/capsule/Makefile` — reference Makefile pattern from FD-002
- [ ] `manifests/plugins/kustomize/capsule/kustomization.yaml` — reference kustomization structure
- [ ] `manifests/plugins/kustomize/capsule/values.yaml` — reference values pattern (resource limits, log level)
- [ ] `manifests/plugins/kustomize/capsule/resources/namespace.yaml` — reference namespace with PSA labels
- [ ] `.forgia/fd/FD-003-openbao-bank-vaults-operator.md` — parent FD architecture
- [ ] `.forgia/fd/FD-003-threat-model.md` — security constraints for operator RBAC

## Constitution Check

- [ ] Respects code standards (YAML 2-space indent, shell `set -euo pipefail`)
- [ ] Respects commit conventions (`feat(FD-003): ...`)
- [ ] No hardcoded secrets (operator image tag, not credentials)
- [ ] Tests defined and sufficient (kustomize build + runtime in SDD-004)

---

## Work Log / Diario di Lavoro

### Agent / Agente

- **Executor**: <!-- openhands | claude-code | manual -->
- **Started**: <!-- timestamp -->
- **Completed**: <!-- timestamp -->
- **Duration / Durata**: <!-- total time -->

### Decisions / Decisioni

1. <!-- decision 1: what and why -->

### Output

- **Commit(s)**: <!-- hash -->
- **PR**: <!-- link -->
- **Files created/modified**:
  - `path/to/file`

### Retrospective / Retrospettiva

- **What worked**:
- **What didn't**:
- **Suggestions for future FDs**:
