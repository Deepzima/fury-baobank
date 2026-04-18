---
id: "SDD-001"
fd: "FD-004"
title: "Consumer Kind cluster + OpenBao exposure"
status: planned
agent: ""
assigned_to: ""
created: "2026-04-18"
started: ""
completed: ""
tags: [cross-cluster, kind, networking]
---

# SDD-001: Consumer Kind cluster + OpenBao exposure

> Parent FD: [[FD-004]]

## Scope

Create a second Kind cluster (`fury-baobank-consumer`) that acts as a customer's independent cluster consuming secrets from the baobank platform. Expose the tenant's OpenBao instance from baobank so it is reachable from the consumer cluster.

Deliverables:

1. **Kind config**: `scenarios/scen-secret-inject/cluster/kind-consumer.yaml` — 1-node Kind cluster, default CNI, no Vault infrastructure.
2. **Docker IP discovery**: The consumer cluster reaches OpenBao on baobank via the baobank Kind node's Docker IP. Discover this IP using `docker inspect` on the baobank control-plane container.
3. **Mise task**: `scen:secret-inject:up` — creates the consumer Kind cluster and resolves the baobank OpenBao endpoint (Docker IP + NodePort). Stores the resolved `VAULT_ADDR` for downstream use.

The consumer cluster is deliberately minimal: no CNI plugins, no operators, no webhooks. It only needs to run pods that can reach the Docker bridge network.

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|-------------------------|-------------|---------------------------|
| `scenarios/scen-secret-inject/cluster/kind-consumer.yaml` | Kind config (YAML) | 1-node cluster definition for fury-baobank-consumer |
| `docker inspect` | Shell command | Discovers baobank node container IP on Docker bridge |
| NodePort on baobank | TCP (8200) | Exposes tenant OpenBao Service to Docker bridge network |
| `scen:secret-inject:up` | Mise task | Creates consumer cluster, resolves VAULT_ADDR |
| `VAULT_ADDR` | Environment variable / file | `http://<baobank-docker-ip>:<nodeport>` — consumed by SDD-002 and SDD-003 |

## Constraints / Vincoli

- Language / Linguaggio: Shell (bash), YAML
- Framework: Kind, Docker, mise
- Dependencies / Dipendenze: Kind CLI, Docker daemon with sufficient resources for 2 clusters simultaneously
- Patterns / Pattern: Shell scripts use `set -euo pipefail`. YAML uses 2-space indent.

### Security (from threat model)

- **NodePort exposes OpenBao to the entire Docker bridge network** — any container on the bridge can reach it, not just the consumer cluster. This is a known lab-only trade-off.
- **Production mitigation**: expose OpenBao via Ingress with TLS termination and IP allowlist. Do NOT use NodePort in production.
- **Documentation requirement**: the script and/or a comment in the Kind config must explicitly document this risk.

## Best Practices

- Error handling: `set -euo pipefail` in all scripts. Fail fast if baobank cluster is not running or OpenBao is not ready.
- Naming: cluster name `fury-baobank-consumer` (matches FD-004 convention). Scenario directory `scenarios/scen-secret-inject/`.
- Style: Kind config follows existing patterns (see `cluster/kind-config.yaml` if present). Mise tasks namespaced under `scen:secret-inject:*`.

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|-------------|-------------|----------|
| Integration | Consumer Kind cluster comes up successfully | `kind get clusters` includes `fury-baobank-consumer` |
| Integration | Docker IP of baobank node is resolvable | `docker inspect` returns a valid IP |
| Integration | OpenBao is reachable from consumer cluster | `curl http://<ip>:<port>/v1/sys/health` returns 200 |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `scenarios/scen-secret-inject/cluster/kind-consumer.yaml` exists and is a valid Kind config
- [ ] `mise run scen:secret-inject:up` creates the `fury-baobank-consumer` Kind cluster
- [ ] Baobank OpenBao Docker IP is discovered via `docker inspect` (not hardcoded)
- [ ] OpenBao on baobank is reachable from a pod on the consumer cluster via `http://<docker-ip>:<nodeport>`
- [ ] NodePort exposure risk is documented in code comments
- [ ] Running two Kind clusters simultaneously does not cause resource issues
- [ ] `mise run scen:secret-inject:down` destroys the consumer cluster cleanly

## Context / Contesto

- [ ] `.forgia/fd/FD-004-cross-cluster-secret-injection.md` — parent FD with architecture diagrams
- [ ] `.forgia/fd/FD-004-threat-model.md` — STRIDE analysis, NodePort exposure risks
- [ ] `tests/07-openbao.bats` — reference BATS structure and OpenBao wait patterns
- [ ] `manifests/plugins/kustomize/openbao-tenant-template/vault-cr-template.yaml` — Vault CR structure, NodePort config

## Constitution Check

- [x] Respects code standards (YAML 2-space indent, shell `set -euo pipefail`)
- [x] Respects commit conventions (`feat(FD-004): ...`)
- [x] No hardcoded secrets (Docker IP discovered at runtime, not hardcoded)
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
  - `scenarios/scen-secret-inject/cluster/kind-consumer.yaml`
  - `mise.toml` (new tasks)

### Retrospective / Retrospettiva

- **What worked / Cosa ha funzionato**:
- **What didn't / Cosa non ha funzionato**:
- **Suggestions for future FDs / Suggerimenti per FD futuri**:
