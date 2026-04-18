---
id: "SDD-002"
fd: "FD-003"
title: "Bank-Vaults webhook kustomize plugin"
status: completed
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-17"
started: "2026-04-17"
completed: "2026-04-17"
tags: [bank-vaults, webhook, kustomize, helm, cert-manager]
---

# SDD-002: Bank-Vaults webhook kustomize plugin

> Parent FD: [[FD-003]]

## Scope

Render the Bank-Vaults vault-secrets-webhook Helm chart (v1.22.x) into a kustomize-buildable bundle at `manifests/plugins/kustomize/bank-vaults-webhook/`. The webhook deploys in `bank-vaults-system` and intercepts pod creation across ALL tenant namespaces to inject secrets from each tenant's dedicated OpenBao instance.

### Deliverables

- `manifests/plugins/kustomize/bank-vaults-webhook/Makefile` — chart pull + `helm template`
- `manifests/plugins/kustomize/bank-vaults-webhook/values.yaml` — replicas (2 for HA), timeoutSeconds, failurePolicy, namespace exemptions, cert-manager config, resource limits
- `manifests/plugins/kustomize/bank-vaults-webhook/kustomization.yaml` — rendered output + patches
- `manifests/plugins/kustomize/bank-vaults-webhook/resources/bank-vaults-webhook-from-helm.yaml` — rendered chart
- `manifests/plugins/kustomize/bank-vaults-webhook/patches/` — cert isCA patch if needed (FD-002 lesson)

### NOT in scope

- Operator (SDD-001), Vault CR (SDD-003), tests (SDD-004), furyctl wiring (SDD-005).

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|---|---|---|
| `Makefile` target `template` | shell (make) | Pulls chart, renders with `helm template` |
| `values.yaml` | YAML | Webhook values: replicas, timeout, failurePolicy, cert-manager, namespaceSelector |
| MutatingWebhookConfiguration | K8s admission | Intercepts pod CREATE in tenant namespaces; exempts system namespaces |
| Webhook Deployment | K8s Deployment | 2 replicas in `bank-vaults-system` |
| cert-manager Certificate | cert-manager CR | Webhook TLS — issued by self-signed Issuer (with `isCA: true` if needed) |
| Pod annotations | Vault annotation contract | `vault.security.banzaicloud.io/vault-addr`, `vault-role`, `vault-path` on target pods |

## Constraints / Vincoli

- Language: YAML, Makefile, shell
- Framework: helm, kustomize, cert-manager
- Chart: `bank-vaults/vault-secrets-webhook` v1.22.x
- Dependencies: SDD-001 must be complete (Vault CRD registered, operator running)
- Patterns:
  - Same render pattern as Capsule and operator (Makefile + values + kustomization)
  - Webhook namespaceSelector must EXEMPT: `bank-vaults-system`, `capsule-system`, `kube-system`, `kube-public`, `kube-node-lease`, `cert-manager`, `local-path-storage`
  - `failurePolicy: Fail` (fail-closed, per constitution)
  - `timeoutSeconds: 5` (DoS mitigation, same as Capsule)

### Security (from threat model)

- Set `failurePolicy: Fail` and `timeoutSeconds: 5` on all webhook configs (source: threat model)
- Verify cert-manager Certificate has `isCA: true` if using self-signed pattern — apply same kustomize patch as FD-002 Capsule fix if needed (source: threat model)
- Set `replicas: 2` for HA — webhook `failurePolicy: Fail` blocks ALL pod creation across ALL tenants if webhook is down (source: threat model)
- Exempt system namespaces from webhook scope (source: threat model)
- BATS: assert webhook `clientConfig.service.namespace` = `bank-vaults-system`, assert no rogue webhook pointing elsewhere (source: threat model)
- **Critical**: verify the webhook authenticates using the TARGET pod's ServiceAccount (not its own global SA). If it uses its own SA, the Vault policy scope per-tenant is broken (source: threat model)

## Best Practices

- Error handling: same Makefile `.tmp → mv` pattern
- Naming: `bank-vaults-webhook-from-helm.yaml`
- Style: provenance header, chart version pinned
- Validate cert-manager integration: after `kustomize build`, check that Certificate and Issuer resources are present

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|---|---|---|
| Unit | `kustomize build` succeeds, produces MutatingWebhookConfiguration | Structural |
| Integration | Webhook Deployment reaches Ready, MutatingWebhookConfiguration registered | Runtime (via SDD-004) |
| E2E | Pod with vault annotation gets secret injected | Via SDD-004 |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `manifests/plugins/kustomize/bank-vaults-webhook/` directory exists with Makefile, values.yaml, kustomization.yaml, resources/
- [ ] `kustomize build` produces valid output with Deployment, MutatingWebhookConfiguration, Certificate, Issuer, RBAC
- [ ] Webhook `failurePolicy: Fail` on all hooks
- [ ] Webhook `timeoutSeconds: 5` on all hooks
- [ ] Webhook namespaceSelector exempts system namespaces
- [ ] Webhook replicas = 2 in values.yaml
- [ ] cert-manager Certificate present with `isCA: true` (or patched)
- [ ] Webhook image pinned by tag
- [ ] `Makefile template` regenerates deterministically

## Context / Contesto

- [ ] `manifests/plugins/kustomize/capsule/patches/certificate-isca.yaml` — reference isCA patch from FD-002
- [ ] `manifests/plugins/kustomize/capsule/values.yaml` — reference webhook timeout/failurePolicy/namespaceSelector pattern
- [ ] `manifests/plugins/kustomize/bank-vaults-operator/` — SDD-001 output (operator must be running before webhook)
- [ ] `.forgia/fd/FD-003-threat-model.md` — webhook security constraints
- [ ] Bank-Vaults webhook docs: how annotations map to Vault API calls, SA authentication flow

## Constitution Check

- [ ] Respects code standards (YAML 2-space, shell `set -euo pipefail`)
- [ ] Respects commit conventions (`feat(FD-003): ...`)
- [ ] No hardcoded secrets
- [ ] Tests defined and sufficient

---

## Work Log / Diario di Lavoro

### Agent / Agente

- **Executor**: claude-code
- **Started**: 2026-04-17
- **Completed**: 2026-04-17
- **Duration / Durata**: ~10 min

### Decisions / Decisioni

1. Webhook chart uses proper two-tier CA (`isCA: true` on CA cert) — no kustomize patch needed unlike the Capsule webhook (FD-002).
2. Set `failurePolicy: Fail`, `timeoutSeconds: 5`, `replicas: 2` in `values.yaml`.

### Output

- **Commit(s)**: part of FD-003 implementation commit
- **PR**: N/A
- **Files created/modified**:
  - `manifests/plugins/kustomize/bank-vaults-webhook/Makefile`
  - `manifests/plugins/kustomize/bank-vaults-webhook/values.yaml`
  - `manifests/plugins/kustomize/bank-vaults-webhook/kustomization.yaml`
  - `manifests/plugins/kustomize/bank-vaults-webhook/resources/vault-secrets-webhook-from-helm.yaml`

### Retrospective / Retrospettiva

- **What worked**: Checking the rendered Certificate confirmed the two-tier CA pattern — no patch needed.
- **What didn't**: N/A, clean implementation.
- **Suggestions for future FDs**: Bank-Vaults webhook chart is better engineered than Capsule for cert-manager integration.
