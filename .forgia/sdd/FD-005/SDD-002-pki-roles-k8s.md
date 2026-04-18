---
id: "SDD-002"
fd: "FD-005"
title: "PKI roles for Kubernetes components"
status: planned
agent: ""
assigned_to: ""
created: "2026-04-18"
started: ""
completed: ""
tags: [pki, roles, kubernetes, apiserver, kubelet, etcd]
---

# SDD-002: PKI roles for Kubernetes components

> Parent FD: [[FD-005]]
> Depends on: [[SDD-001]] (PKI engines must be mounted and CA chain established)
> Consumed by: [[SDD-003]], [[SDD-004]]

## Scope

Create PKI roles on the `pki-k8s/` engine for issuing certificates to Kubernetes components. Each role enforces specific constraints matching K8s PKI requirements.

What to build:

1. **Role `k8s-apiserver`** -- server auth certificates for the API server
   - allowed_domains: kubernetes, kubernetes.default, kubernetes.default.svc, kubernetes.default.svc.cluster.local
   - allowed_uri_sans: (none)
   - ip_sans: 10.96.0.1 (ClusterIP), 127.0.0.1
   - key_usage: DigitalSignature, KeyEncipherment
   - ext_key_usage: ServerAuth
   - max_ttl: 24h, key_bits: 2048, enforce_hostnames: true
   - allow_subdomains: false, allow_bare_domains: true

2. **Role `k8s-kubelet`** -- client auth certificates for kubelet
   - allowed_domains: system:node
   - allow_subdomains: true (for system:node:*)
   - organization: system:nodes
   - key_usage: DigitalSignature, KeyEncipherment
   - ext_key_usage: ClientAuth
   - max_ttl: 24h, key_bits: 2048, enforce_hostnames: false (CN contains colons)

3. **Role `k8s-etcd`** -- server+client auth certificates for etcd
   - allowed_domains: etcd, etcd.kube-system.svc, etcd.kube-system.svc.cluster.local, localhost
   - ip_sans: 127.0.0.1
   - key_usage: DigitalSignature, KeyEncipherment
   - ext_key_usage: ServerAuth, ClientAuth
   - max_ttl: 24h, key_bits: 2048, enforce_hostnames: true

4. **Role `k8s-front-proxy`** -- client auth only for front proxy
   - allowed_domains: front-proxy-client
   - key_usage: DigitalSignature, KeyEncipherment
   - ext_key_usage: ClientAuth
   - max_ttl: 24h, key_bits: 2048, enforce_hostnames: false

5. **Script** at `scenarios/scen-pki-ca/scripts/setup-roles.sh` (or appended to setup-pki.sh)

## Interfaces

| Interface | Type | Description |
|-----------|------|-------------|
| `pki-k8s/roles/k8s-apiserver` | Vault role | Issues server auth certs for kube-apiserver |
| `pki-k8s/roles/k8s-kubelet` | Vault role | Issues client auth certs for kubelets |
| `pki-k8s/roles/k8s-etcd` | Vault role | Issues server+client auth certs for etcd |
| `pki-k8s/roles/k8s-front-proxy` | Vault role | Issues client auth certs for front proxy |
| `scenarios/scen-pki-ca/scripts/setup-roles.sh` | shell script | Creates all 4 roles, requires VAULT_ADDR and VAULT_TOKEN |

## Constraints

- Language: Bash with `set -euo pipefail`
- Dependencies: `vault` CLI, `jq`
- All roles: max_ttl=24h, key_bits >= 2048
- All roles: enforce_hostnames=true where applicable (false for kubelet and front-proxy due to CN format)
- No wildcard domains on k8s-apiserver -- explicit allowed_domains only

### Security (from threat model)

- Every role MUST set enforce_hostnames=true (except kubelet/front-proxy where CN contains colons or non-hostname chars)
- Every role MUST set max_ttl=24h (short-lived certs)
- Every role MUST set key_bits >= 2048
- k8s-apiserver: explicit allowed_domains only, NO wildcards, NO allow_any_name
- BATS: attempt to issue a cert with unauthorized SAN -- must be rejected by Vault
- BATS: verify each role's allowed_domains and key_usage match the specification

## Best Practices

- Script is idempotent: uses `vault write` which is an upsert on roles
- Each role created with explicit parameters (no reliance on defaults)
- Log each role creation to stderr for debugging
- Validate role configuration after creation by reading it back

## Test Requirements

| Type | What | Coverage |
|------|------|----------|
| BATS | k8s-apiserver role exists with correct allowed_domains | 1 test |
| BATS | k8s-kubelet role exists with correct organization | 1 test |
| BATS | k8s-etcd role exists with correct ext_key_usage (ServerAuth+ClientAuth) | 1 test |
| BATS | k8s-front-proxy role exists with ClientAuth only | 1 test |
| BATS | All roles have max_ttl <= 24h | 1 test |
| BATS | All roles have key_bits >= 2048 | 1 test |
| BATS | Attempt unauthorized SAN on k8s-apiserver -- must fail | 1 test |
| BATS | Attempt to issue cert with TTL > 24h -- must fail | 1 test |

**Minimum: 8 BATS tests** (in `tests/09-pki.bats`)

## Acceptance Criteria

- [ ] 4 roles created on `pki-k8s/`: k8s-apiserver, k8s-kubelet, k8s-etcd, k8s-front-proxy
- [ ] k8s-apiserver: server auth, explicit SANs (kubernetes, kubernetes.default, etc.), IP SAN 10.96.0.1
- [ ] k8s-kubelet: client auth, CN=system:node:*, O=system:nodes
- [ ] k8s-etcd: server+client auth, SANs for etcd hosts
- [ ] k8s-front-proxy: client auth only
- [ ] All roles: max_ttl=24h, key_bits >= 2048
- [ ] Unauthorized SAN issuance is rejected
- [ ] Setup script is idempotent
- [ ] All BATS tests pass

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
- [x] Tests defined and sufficient (8 BATS tests)

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
