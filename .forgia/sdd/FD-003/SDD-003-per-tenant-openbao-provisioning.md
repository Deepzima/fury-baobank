---
id: "SDD-003"
fd: "FD-003"
title: "Per-tenant OpenBao provisioning via Vault CR"
status: assigned
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-17"
started: ""
completed: ""
tags: [openbao, vault-cr, per-tenant, provisioning]
---

# SDD-003: Per-tenant OpenBao provisioning via Vault CR

> Parent FD: [[FD-003]]

## Scope

Define a reusable `Vault` CR template that provisions a dedicated OpenBao instance per tenant. Deploy 2 test tenants to validate the pattern:

- `reevo-ob-id-alpha` in namespace `bats-tenant-alpha` (Capsule Tenant)
- `reevo-ob-id-beta` in namespace `bats-tenant-beta` (Capsule Tenant)

Each instance gets: OpenBao StatefulSet with Raft storage, auto-unseal via K8s Secret in its own namespace, KV-v2 secret engine, Kubernetes auth method bound to the tenant namespace, TLS on the listener, and a file audit backend.

### Deliverables

- `manifests/plugins/kustomize/openbao-tenant-template/vault-cr-template.yaml` — reusable Vault CR template with placeholder tenant name
- `tests/fixtures/tenant-alpha-vault-cr.yaml` — instantiated Vault CR for test tenant alpha
- `tests/fixtures/tenant-beta-vault-cr.yaml` — instantiated Vault CR for test tenant beta
- `tests/fixtures/tenant-alpha-capsule.yaml` — Capsule Tenant CR for alpha
- `tests/fixtures/tenant-beta-capsule.yaml` — Capsule Tenant CR for beta
- `tests/fixtures/tenant-alpha-netpol.yaml` — default-deny NetworkPolicy for alpha namespace
- `tests/fixtures/tenant-beta-netpol.yaml` — default-deny NetworkPolicy for beta namespace

### NOT in scope

- Operator plugin (SDD-001), webhook plugin (SDD-002), BATS tests (SDD-004), furyctl wiring (SDD-005).

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|---|---|---|
| Vault CR (`reevo-ob-id-<name>`) | K8s CR (`vault.banzaicloud.com/v1alpha1`) | Declares a per-tenant OpenBao instance: image, unseal config, externalConfig (policies, auth, secrets) |
| Capsule Tenant CR | K8s CR (`capsule.clastix.io/v1beta2`) | Creates the tenant namespace with owner, quota, nodeSelector |
| OpenBao StatefulSet | K8s StatefulSet (created by operator) | 1 replica per tenant (lab sizing), Raft storage, TLS listener on :8200 |
| K8s Secret (unseal keys) | K8s Secret (created by operator) | Per-tenant unseal keys + root token, in tenant namespace |
| OpenBao Service | K8s Service (ClusterIP) | `reevo-ob-id-<name>.<namespace>:8200` — tenant's Vault endpoint |
| Kubernetes auth role | Vault auth config | Bound to `bound_service_account_namespaces: ["<tenant-ns>"]` — only SAs from the tenant namespace can authenticate |
| KV-v2 engine | Vault secret engine | Mounted at `secret/` — tenant has full CRUD on `secret/*` |
| NetworkPolicy | K8s NetworkPolicy | Default-deny ingress/egress + allow same-namespace + allow DNS — prevents cross-tenant network access |

## Constraints / Vincoli

- Language: YAML
- Framework: K8s CRs (Vault, Capsule Tenant, NetworkPolicy)
- Dependencies: SDD-001 (operator running), SDD-002 (webhook running), Capsule (FD-002)
- OpenBao image: `ghcr.io/openbao/openbao:2.1.0` (pinned < 2.2.0 to avoid service registration label break)
- Patterns:
  - Vault CR naming: `reevo-ob-id-<identifier>` (product naming convention)
  - One Vault CR per tenant namespace (operator creates StatefulSet in same namespace)
  - `unsealConfig.kubernetes.secretNamespace` = tenant namespace (keys stay in tenant scope)
  - `externalConfig` declares policies, auth, secrets — operator reconciles (config-as-code)
  - TLS on listener: cert-manager Certificate in tenant namespace or operator-managed TLS
  - Audit backend: `file` type, path `/vault/logs/audit.log`
  - Resource sizing per instance: requests 100m CPU / 256Mi RAM, limits 500m CPU / 512Mi RAM

### Security (from threat model)

- Enable TLS on OpenBao listener — without TLS, secrets are plaintext on the wire within the namespace (source: threat model)
- Enable `file` audit backend in the Vault CR template — per-tenant accountability (source: threat model)
- Pin OpenBao image `ghcr.io/openbao/openbao:2.1.0` — all instances use the same verified image (source: threat model)
- Kubernetes auth roles: `bound_service_account_namespaces` MUST match the tenant namespace exactly — NO wildcards `["*"]` (source: threat model)
- Inject a default-deny NetworkPolicy into each tenant namespace — this is the PRIMARY cross-tenant isolation boundary. Allow only: same-namespace, kube-dns (53/UDP+TCP), and optionally egress to internet (source: threat model)
- RBAC: restrict `create/update/delete` on `vaults.vault.banzaicloud.com` to cluster-admin only — tenant users must NOT self-provision Vault instances (source: threat model)
- Do NOT store root token or unseal key values in any committed YAML — the Vault CR `unsealConfig` references a Secret by name (source: threat model)

## Best Practices

- Error handling: Vault CR `externalConfig` is declarative — if a policy or auth config is invalid, the operator logs the error and retries. No manual intervention needed.
- Naming: `reevo-ob-id-<identifier>` for Vault CR name, namespace = tenant Capsule namespace
- Style: YAML 2-space indent, comments explaining each section of the Vault CR spec
- Template reusability: the template should be parameterizable (sed/envsubst for tenant name)

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|---|---|---|
| Unit | Vault CR YAML validates against CRD schema (`kubeconform`) | Structural |
| Integration | Both test tenants: StatefulSet Running, `vault status` initialized + unsealed | Runtime (via SDD-004) |
| E2E | Write/read secret on each instance, Kubernetes auth works per-tenant | Via SDD-004 |

## Acceptance Criteria / Criteri di Accettazione

- [ ] Vault CR template exists with all required fields: image, unsealConfig, externalConfig (policies, auth, secrets), TLS, audit
- [ ] 2 test tenant fixtures exist (alpha + beta) with Capsule Tenant + Vault CR + NetworkPolicy each
- [ ] Both instances: operator creates StatefulSet, pod Running
- [ ] Both instances: auto-unsealed (no manual keys submission)
- [ ] Both instances: `vault status` shows initialized + unsealed + TLS enabled
- [ ] Both instances: KV-v2 at `secret/` enabled, write/read works
- [ ] Both instances: Kubernetes auth role bound to correct tenant namespace only
- [ ] NetworkPolicy in each tenant namespace blocks cross-tenant traffic
- [ ] No `["*"]` in `bound_service_account_names` or `bound_service_account_namespaces` in any auth role
- [ ] OpenBao image matches `ghcr.io/openbao/openbao:2.1.0` on running pods

## Context / Contesto

- [ ] `docs/ARCHITECTURE.md` — C4 diagrams for Bank-Vaults + OpenBao
- [ ] `.forgia/fd/FD-003-openbao-bank-vaults-operator.md` — per-tenant architecture, data flow
- [ ] `.forgia/fd/FD-003-threat-model.md` — per-tenant threat model, NetworkPolicy requirement
- [ ] `tests/06-capsule.bats` — reference for Capsule Tenant CR creation in tests (setup_file/teardown_file pattern)
- [ ] Bank-Vaults Vault CR spec: https://github.com/bank-vaults/vault-operator/blob/main/pkg/apis/vault/v1alpha1/vault_types.go
- [ ] Bank-Vaults example Vault CR with externalConfig: community example from bank-vaults/bank-vaults#3543

## Constitution Check

- [ ] Respects code standards (YAML 2-space indent)
- [ ] Respects commit conventions (`feat(FD-003): ...`)
- [ ] No hardcoded secrets (unsealConfig references Secret by name, not values)
- [ ] Tests defined and sufficient (via SDD-004)

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
