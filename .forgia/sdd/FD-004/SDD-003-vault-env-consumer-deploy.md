---
id: "SDD-003"
fd: "FD-004"
title: "vault-env consumer deployment"
status: planned
agent: ""
assigned_to: ""
created: "2026-04-18"
started: ""
completed: ""
tags: [vault-env, init-container, deployment]
---

# SDD-003: vault-env consumer deployment

> Parent FD: [[FD-004]]

## Scope

Deploy an application pod on the consumer cluster that transparently receives secrets from the baobank tenant's OpenBao via the `vault-env` init container and AppRole authentication. The app has zero Vault awareness — it reads `DB_PASSWORD` from a plain environment variable.

Deliverables:

1. **K8s Secret manifest**: `scenarios/scen-secret-inject/manifests/approle-credentials.yaml` — template for the K8s Secret holding `role_id` and `secret_id`. Values are placeholders (`ROLE_ID_PLACEHOLDER`, `SECRET_ID_PLACEHOLDER`) to be substituted at deploy time from SDD-002 output. Never committed with real credentials.
2. **App deployment manifest**: `scenarios/scen-secret-inject/manifests/consumer-app.yaml` — Pod/Deployment with:
   - Init container: `ghcr.io/bank-vaults/vault-env:v1.22.1` performing AppRole login and secret fetch
   - Environment variables on the main container: `DB_PASSWORD=vault:secret/data/acme/db#password`
   - `VAULT_ADDR` pointing to the baobank OpenBao endpoint (from SDD-001)
   - `VAULT_AUTH_METHOD=approle`
   - `VAULT_ROLE_ID` and `VAULT_SECRET_ID` sourced from the K8s Secret
   - `VAULT_CLIENT_TIMEOUT=10s`
3. **Deploy script**: `scenarios/scen-secret-inject/scripts/deploy-consumer-app.sh` — substitutes real `role_id`/`secret_id` into the Secret manifest, applies manifests to consumer cluster, waits for pod readiness.

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|-------------------------|-------------|---------------------------|
| `approle-credentials.yaml` | K8s Secret (YAML) | Template with `ROLE_ID_PLACEHOLDER` / `SECRET_ID_PLACEHOLDER` — substituted at deploy time |
| `consumer-app.yaml` | K8s Deployment (YAML) | App pod with vault-env init container, env var references |
| `deploy-consumer-app.sh` | Shell script | Substitutes creds, applies manifests, waits for readiness |
| vault-env init container | Container image | `ghcr.io/bank-vaults/vault-env:v1.22.1` — authenticates via AppRole, injects env vars |
| `VAULT_ADDR` | Env var | `http://<baobank-docker-ip>:<nodeport>` — OpenBao endpoint from SDD-001 |
| `DB_PASSWORD` | Env var (injected) | `vault:secret/data/acme/db#password` — resolved by vault-env to actual secret value |

## Constraints / Vincoli

- Language / Linguaggio: Bash (script), YAML (manifests)
- Framework: Kubernetes, vault-env (Bank-Vaults)
- Dependencies / Dipendenze: SDD-001 (consumer cluster + VAULT_ADDR), SDD-002 (role_id + secret_id), vault-env image pullable from consumer cluster
- Patterns / Pattern: `set -euo pipefail` in scripts. YAML 2-space indent. Manifest placeholders for secrets (never real values in YAML files).

### Security (from threat model)

- **Pin vault-env image by tag**: use `ghcr.io/bank-vaults/vault-env:v1.22.1` exactly. Do not use `:latest` or floating tags. Ideally pin by digest in production.
- **`VAULT_CLIENT_TIMEOUT=10s`**: prevents vault-env from hanging indefinitely if OpenBao is unreachable. Pod restart policy handles transient failures.
- **BATS verification**: verify the running init container image matches the expected tag `v1.22.1`.
- **AppRole credentials in K8s Secret only**: `role_id` and `secret_id` are never hardcoded in deployment YAML. The Secret manifest uses placeholders substituted at deploy time by the script.
- **Env var exposure**: secrets injected as env vars are visible in `/proc/*/environ`. Accepted for lab — documented as production concern (use Vault Agent with tmpfs for production).

## Best Practices

- Error handling: `set -euo pipefail` in deploy script. Fail if consumer cluster context is not set. Fail if role_id/secret_id are empty.
- Naming: consumer app namespace `consumer-app`. Deployment name `secret-consumer`. Secret name `approle-credentials`.
- Style: Manifests use standard K8s labels (`app.kubernetes.io/name`, `app.kubernetes.io/part-of`). Comments in YAML explain vault-env env vars.

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|-------------|-------------|----------|
| Integration | vault-env init container completes successfully (exit 0) | Pod events show init container completed |
| Integration | Main container starts with `DB_PASSWORD` set to `s3cret` | `kubectl exec ... -- env \| grep DB_PASSWORD` |
| Integration | Running init container image matches expected tag | `kubectl get pod -o jsonpath='{.spec.initContainers[0].image}'` returns `v1.22.1` |
| Security | AppRole credentials are in K8s Secret, not in deployment YAML | Grep deployment manifest for `role_id` / `secret_id` literals returns nothing |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `scenarios/scen-secret-inject/manifests/approle-credentials.yaml` exists with placeholder values (no real secrets)
- [ ] `scenarios/scen-secret-inject/manifests/consumer-app.yaml` exists with vault-env init container
- [ ] vault-env image is pinned to `ghcr.io/bank-vaults/vault-env:v1.22.1`
- [ ] `VAULT_CLIENT_TIMEOUT=10s` is set on the init container
- [ ] `DB_PASSWORD=vault:secret/data/acme/db#password` is set on the main container
- [ ] `scenarios/scen-secret-inject/scripts/deploy-consumer-app.sh` substitutes credentials at deploy time
- [ ] Deploy script uses `set -euo pipefail`
- [ ] App pod on consumer cluster starts and main container has `DB_PASSWORD=s3cret`
- [ ] No real credentials are committed to any YAML file

## Context / Contesto

- [ ] `.forgia/fd/FD-004-cross-cluster-secret-injection.md` — vault-env architecture, data flow sequence diagram
- [ ] `.forgia/fd/FD-004-threat-model.md` — vault-env init container threats, image pinning requirement
- [ ] `tests/07-openbao.bats` — reference BATS structure for pod readiness waits
- [ ] `manifests/plugins/kustomize/openbao-tenant-template/vault-cr-template.yaml` — Vault CR and image pinning patterns

## Constitution Check

- [x] Respects code standards (YAML 2-space indent, shell `set -euo pipefail`)
- [x] Respects commit conventions (`feat(FD-004): ...`)
- [x] No hardcoded secrets (AppRole creds in K8s Secret with placeholders, substituted at deploy time)
- [x] Tests defined and sufficient

---

## Work Log / Diario di Lavoro

> This section is **mandatory**. Must be filled by the agent or developer during and after execution.

### Agent / Agente

- **Executor**: <!-- openhands | claude-code | manual | name -->
- **Started**: <!-- timestamp -->
- **Completed**: <!-- timestamp -->
- **Duration / Durata**: <!-- total time -->

### Decisions / Decisioni

1. <!-- decision 1: what and why -->

### Output

- **Commit(s)**: <!-- hash -->
- **PR**: <!-- link -->
- **Files created/modified**:
  - `scenarios/scen-secret-inject/manifests/approle-credentials.yaml`
  - `scenarios/scen-secret-inject/manifests/consumer-app.yaml`
  - `scenarios/scen-secret-inject/scripts/deploy-consumer-app.sh`

### Retrospective / Retrospettiva

- **What worked / Cosa ha funzionato**:
- **What didn't / Cosa non ha funzionato**:
- **Suggestions for future FDs / Suggerimenti per FD futuri**:
