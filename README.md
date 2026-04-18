# fury-baobank

PoC lab validating **OpenBao-as-a-Service** on Kubernetes Fury Distribution — multi-tenant secret management where each customer gets a dedicated, isolated Vault instance.

## Stack

| Layer | Component | FD | Tests |
|---|---|---|---|
| Network | Cilium (kube-proxy-replacement, Hubble mTLS) | FD-001 | 26 |
| Tenancy | Capsule (multi-tenant controller, quota, nodeSelector) | FD-002 | 12 |
| Secrets | Bank-Vaults operator + webhook, per-tenant OpenBao | FD-003 | 19+2 |
| **Total** | | | **59 BATS** |

## Quick start

```bash
# Install tools
mise install

# Full stack: Kind cluster → Cilium → Capsule → Bank-Vaults → 59 BATS tests
mise run all
```

## Scenarios (opt-in, isolated from main tests)

| Scenario | FD | What it validates |
|---|---|---|
| [scen-secret-inject](scenarios/scen-secret-inject/) | FD-004 | Cross-cluster: consumer Kind cluster reads secrets from baobank OpenBao via AppRole + vault-env |
| scen-pki-ca | FD-005 | PKI/CA: OpenBao as Root+Intermediate CA for K8s certificates, revocation via CRL |
| scen-hsm-transit | FD-006 | Premium tier: HSM-backed unseal (softhsm-kube) + etcd encryption via Transit KMS v2 |

### Run a scenario

```bash
# Cross-cluster secret injection (FD-004)
bash scenarios/scen-secret-inject/scripts/setup-consumer.sh
bash scenarios/scen-secret-inject/scripts/provision-approle.sh
bash scenarios/scen-secret-inject/scripts/deploy-consumer-app.sh
mise run scen:secret-inject:test

# Cleanup
mise run scen:secret-inject:down
```

## Structure

```
fury-baobank/
├── cluster/                          Kind cluster config (3 nodes)
├── furyctl.yaml                      KFD distribution (Cilium + plugins)
├── mise.toml                         Task definitions
├── manifests/
│   ├── overrides/                    Cilium kube-proxy-replacement patches
│   └── plugins/kustomize/
│       ├── capsule/                  Capsule v0.12.4 (FD-002)
│       ├── bank-vaults-operator/     Operator v1.23.4 (FD-003)
│       ├── bank-vaults-webhook/      Webhook v1.22.2 (FD-003)
│       └── openbao-tenant-template/  Vault CR template for per-tenant instances
├── scenarios/
│   └── scen-secret-inject/           Cross-cluster injection (FD-004)
│       ├── cluster/                  Consumer Kind config
│       ├── manifests/
│       │   ├── tenant-bao/           Baobank-side: Capsule tenant + OpenBao + NodePort
│       │   └── tenant-env/           Consumer-side: app + vault-env init container
│       ├── scripts/                  setup, provision, deploy, teardown
│       └── tests/                    Scenario-specific BATS
├── tests/
│   ├── 00-cluster.bats → 06-capsule.bats   Infrastructure tests (FD-001/002)
│   ├── 07-openbao.bats                      Per-tenant OpenBao + isolation (FD-003)
│   ├── fixtures/                            Test tenant fixtures
│   └── helpers.bash                         Shared BATS helpers
├── scripts/                          Cilium override render, Hubble mTLS check
├── docs/                             Architecture (C4 diagrams), Hubble queries
└── .forgia/                          Forgia vault (FDs, SDDs, threat models)
```

## Mise tasks

| Task | Description |
|---|---|
| `mise run all` | Full E2E: up → install-cni → 59 BATS tests |
| `mise run up` | Create Kind cluster + label workers |
| `mise run install-cni` | furyctl apply (Cilium + Capsule + Bank-Vaults) |
| `mise run test` | Run all BATS tests |
| `mise run down` | Delete Kind cluster |
| `mise run capsule:template` | Regenerate Capsule kustomize bundle from chart |
| `mise run bank-vaults:template` | Regenerate operator + webhook bundles |
| `mise run scen:secret-inject:*` | Cross-cluster scenario lifecycle |

## Architecture decisions

- **Per-tenant OpenBao** (not shared) — physical isolation, each customer owns their Vault instance
- **OpenBao** (not HashiCorp Vault) — MPL 2.0 license, API-compatible, Linux Foundation governance
- **Bank-Vaults operator** — config-as-code via Vault CR, auto-unseal, zero CLI for steady-state
- **Capsule** (not manual namespaces) — automated tenant onboarding with quota + RBAC + nodeSelector
- **Cilium** (not kube-proxy) — kube-proxy-replacement, Hubble observability, mTLS

## Upstream findings

| ID | Project | Issue |
|---|---|---|
| CAPSULE-001 | projectcapsule/capsule | Chart cert-manager Certificate missing `isCA: true` — breaks Go strict x509 |
| CAPSULE-002 | projectcapsule/capsule | Default webhook blocks capsule-system namespace creation (bootstrap chicken-and-egg) |
| BANK-VAULTS-001 | bank-vaults/vault-operator | Operator doesn't create ServiceAccount or RBAC for sidecar |
| BANK-VAULTS-002 | bank-vaults/vault-operator | `OPERATOR_LOG_LEVEL=debug` hardcoded, no values override |
| BANK-VAULTS-003 | bank-vaults/bank-vaults | No docs for OpenBao path differences (`/openbao/` vs `/vault/`) |

See [cncf/capsule-isca-bug-report.md](../../cncf/capsule-isca-bug-report.md) for the full Capsule bug report.

## References

- [OpenBao](https://openbao.org/) — MPL 2.0 Vault fork
- [Bank-Vaults](https://bank-vaults.dev/docs/) — operator + webhook
- [Capsule](https://projectcapsule.dev/) — multi-tenancy controller
- [KFD](https://docs.sighup.io/) — Kubernetes Fury Distribution
- [softhsm-kube](https://github.com/Deepzima/softhsm-kube) — SoftHSM2 as K8s pod (companion repo for FD-006)
