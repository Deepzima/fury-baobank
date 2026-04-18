# fury-baobank — Architecture

Lab for testing **OpenBao** + **Bank-Vaults** together on Kubernetes Fury Distribution.

## System Context (C4 Level 1)

High-level view of the actors and the system boundary.

```mermaid
flowchart TB
    subgraph actors ["Actors"]
        operator["Platform Operator"]
        appPod["Application Pod"]
    end

    subgraph tenant ["Tenant — Capsule Isolated"]
        subgraph mgmt ["Management Plane"]
            bvOperator["Bank-Vaults Operator"]
            bvWebhook["Bank-Vaults Webhook"]
            vaultCR["Vault CR"]
        end

        subgraph data ["Data Plane"]
            openBao["OpenBao StatefulSet"]
            storage["PV — Raft backend"]
        end
    end

    subgraph external ["External"]
        unsealKMS["Unseal Key Store"]
    end

    operator -->|"kubectl apply"| vaultCR
    vaultCR -->|"watched by"| bvOperator
    bvOperator -->|"deploys"| openBao
    openBao -->|"persists"| storage
    bvOperator -->|"unseal via"| unsealKMS
    appPod -->|"intercepted by"| bvWebhook
    bvWebhook -->|"fetches secret"| openBao

    classDef ext fill:#f0f0f0,stroke:#999
    classDef new fill:#d4edda,stroke:#28a745
    classDef actor fill:#fff3cd,stroke:#ffc107
    class external ext
    class tenant,mgmt,data new
    class actors actor
```

## Container Diagram (C4 Level 2)

Components deployed inside the cluster, their namespaces and relationships.

```mermaid
flowchart TB
    subgraph cluster ["KFD Cluster"]
        subgraph bvSystem ["bank-vaults-system namespace"]
            operatorPod["bank-vaults-operator Deployment"]
            webhookPod["vault-secrets-webhook Deployment"]
        end

        subgraph vaultNs ["openbao namespace"]
            vaultCR["Vault CR<br/>declarative config"]
            baoSts["openbao-0, openbao-1, openbao-2<br/>StatefulSet HA"]
            raftStorage["Raft storage<br/>PV per replica"]
            unsealSecret["K8s Secret<br/>encrypted unseal keys"]
            baoSvc["openbao Service<br/>ClusterIP"]
        end

        subgraph appNs ["apps namespace"]
            userApp["User Application<br/>Pod with annotation"]
            appSA["ServiceAccount<br/>kubernetes auth role"]
        end

        subgraph monitoring ["monitoring namespace"]
            prometheus["Prometheus<br/>scrapes OpenBao metrics"]
        end
    end

    operatorPod -->|"reconcile"| vaultCR
    operatorPod -->|"deploy + unseal"| baoSts
    operatorPod -->|"read keys"| unsealSecret
    baoSts -->|"persist"| raftStorage
    baoSts -->|"exposed by"| baoSvc

    userApp -->|"admission"| webhookPod
    webhookPod -->|"auth via"| appSA
    webhookPod -->|"read secret"| baoSvc

    prometheus -->|"metrics"| baoSvc

    classDef mgmt fill:#d4edda,stroke:#28a745
    classDef data fill:#e3f2fd,stroke:#1976d2
    classDef app fill:#fff3cd,stroke:#ffc107
    classDef obs fill:#fff3e0,stroke:#f57c00
    class bvSystem mgmt
    class vaultNs data
    class appNs app
    class monitoring obs
```

## Flow: Secret Injection

How an application receives secrets without any Vault-aware code.

```mermaid
sequenceDiagram
    autonumber
    participant User as Platform Operator
    participant K8s as K8s API Server
    participant Webhook as Bank-Vaults Webhook
    participant OpenBao as OpenBao
    participant Pod as App Pod

    User->>K8s: apply Deployment with vault annotation
    K8s->>Webhook: AdmissionReview (pod creation)
    Webhook->>Webhook: detect "vault:secret/*" in env
    Webhook->>OpenBao: auth via K8s ServiceAccount token
    OpenBao-->>Webhook: Vault token + policy
    Webhook->>OpenBao: read secret/data/myapp
    OpenBao-->>Webhook: secret value
    Webhook-->>K8s: mutate pod spec with real env values
    K8s->>Pod: create pod with injected secrets
    Pod->>Pod: app reads DB_PASSWORD as normal env var

    Note over Pod,OpenBao: App never talks to OpenBao directly
```

## Flow: Auto-Unseal

How OpenBao recovers after restart without human intervention.

```mermaid
sequenceDiagram
    autonumber
    participant Operator as Bank-Vaults Operator
    participant OpenBao as OpenBao Pod
    participant KMS as Unseal Key Store
    participant K8sSecret as K8s Secret

    Note over Operator,K8sSecret: First startup
    Operator->>OpenBao: start StatefulSet
    OpenBao->>OpenBao: seal state (cannot read data)
    Operator->>OpenBao: initialize
    OpenBao-->>Operator: 5 unseal keys + root token
    Operator->>KMS: encrypt keys with KMS key
    Operator->>K8sSecret: store encrypted keys

    Note over Operator,K8sSecret: Restart after crash or update
    OpenBao->>OpenBao: pod restart, seal state
    Operator->>K8sSecret: fetch encrypted keys
    Operator->>KMS: decrypt keys
    KMS-->>Operator: plaintext unseal keys
    Operator->>OpenBao: submit 3 of 5 unseal keys
    OpenBao->>OpenBao: unsealed, serves requests
```

## Component Responsibilities

| Component | Responsibility | Namespace |
| --- | --- | --- |
| **Bank-Vaults Operator** | Reconciles `Vault` CRs, deploys OpenBao StatefulSet, manages unseal lifecycle | `bank-vaults-system` |
| **Bank-Vaults Webhook** | Intercepts pod creation, detects Vault annotations, injects secrets | `bank-vaults-system` |
| **OpenBao** | Secret storage, encryption, policy enforcement | `openbao` |
| **Vault CR** | Declarative configuration for a Vault instance (policies, auth methods, engines) | `openbao` |
| **Unseal Secret** | K8s Secret holding encrypted unseal keys | `openbao` |
| **Application** | Consumes secrets via injection — no Vault client code | `apps` |
| **ServiceAccount** | K8s identity used by the app to authenticate to OpenBao via Kubernetes auth method | `apps` |

## Decisions

### Why OpenBao instead of Vault

- Open source under MPL 2.0 (no HashiCorp BSL)
- API-compatible with Vault, so Bank-Vaults tooling should work ^[inferred]
- Linux Foundation governance

### Why Bank-Vaults

- Automates init, unseal, and config that would otherwise require manual steps
- Transparent secret injection via mutating webhook — no app code changes
- Kubernetes-native CRD interface (`Vault` CR)

### Why Raft as storage backend

- Built into OpenBao, no external dependency (Consul)
- HA with 3 replicas, leader election handled natively
- Persistent via StatefulSet PVCs

### Why local K8s Secret for unseal (lab only)

- Simpler than integrating AWS KMS / GCP KMS / HSM in a local Kind cluster
- Not production-safe — production uses cloud KMS or HSM

## Scope — What This Lab Validates

### Completed (59 BATS tests)

- **FD-001**: Kind 3-node cluster + Cilium CNI with kube-proxy-replacement + Hubble mTLS
- **FD-002**: Capsule multi-tenancy (Tenant CRs, quota, namespace isolation, webhook enforcement)
- **FD-003**: Bank-Vaults Operator deploys per-tenant OpenBao instances (not shared — each tenant has its own StatefulSet, Raft storage, unseal keys, KV-v2, Kubernetes auth)
- Auto-unseal works with K8s Secret (lab-only; HSM upgrade planned in FD-006)
- Bank-Vaults Webhook injects secrets into pods via annotations
- Cross-tenant isolation: auth binding, RBAC, no wildcard namespaces

### In-Progress Scenarios

- **FD-004** (scen-secret-inject): Cross-cluster secret consumption — consumer Kind cluster reads secrets from baobank OpenBao via AppRole + vault-env init container
- **FD-005** (scen-pki-ca): PKI/CA engine — OpenBao as two-tier CA (Root → Intermediate) for K8s-compatible certificates with SAN validation, revocation, CRL
- **FD-006** (scen-hsm-transit): Premium security tier — HSM-backed unseal via softhsm-kube + etcd encryption-at-rest via Transit KMS v2

### Out of Scope

- Cloud KMS unseal (AWS/GCP/Azure) — lab is Kind-only
- Cross-cluster replication
- Vaultwarden for human password management
- Production hardening (TLS everywhere, HA OpenBao replicas, backup/restore)
