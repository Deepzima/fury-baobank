---
id: "SDD-001"
fd: "FD-001"
title: "Kind cluster config with role labels and cni:none"
status: completed
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-15"
started: ""
completed: ""
tags: [kind, zlab, infrastructure]
---

# SDD-001: Kind cluster config with role labels and cni:none

> Parent FD: [[FD-001]]

## Scope

Write `.zlab.yaml` that declares a 3-node Kind cluster: 1 control-plane and 2 worker nodes with the label `node-role.fury.io/infra=true`. Disable Kind's built-in CNI (`cni: none`) so Cilium can be installed afterward via furyctl. Configure port mappings for lab services bound to loopback. Pin `kindest/node` image by SHA256 digest. Provide a `mise run up` task that invokes `zlab up` and waits until the control-plane is Ready.

Out of scope: Cilium installation (SDD-002), Hubble (SDD-003), BATS tests (SDD-004).

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|---|---|---|
| `.zlab.yaml` | YAML file | zlab config with 3 nodes, `cni: none`, `kindest/node@sha256:...` digest pin, infra labels, port mappings bound to `127.0.0.1` |
| `mise.toml` task `up` | mise task | Invokes `zlab up`, waits for control-plane Ready, exits 0 on success |
| Kubeconfig | File | `~/.kube/config` context `kind-fury-baobank`, permissions `0600` |
| Node labels | K8s resource | `node-role.fury.io/infra=true` on worker nodes (applied post-cluster via `kubectl label`, not via Kind config since Kind doesn't support arbitrary labels natively) |

## Constraints / Vincoli

- Language: YAML (zlab config), TOML (mise task)
- Framework: zlab v0.4.0+, Kind v0.24+, K8s 1.31
- Dependencies: Docker (desktop or colima), mise
- Patterns:
  - `cni: none` is mandatory — no built-in addon; Cilium is installed in SDD-002
  - `kindest/node` pinned by `@sha256:` digest, not by tag
  - Port mappings use `listenAddress: 127.0.0.1` — never `0.0.0.0`
  - Infra labels applied via `kubectl label nodes` after cluster-up, scripted in the same `up` task

### Security (from threat model)

- Pin the `kindest/node` image by digest in `.zlab.yaml` (not a tag like `v1.31.0`). Document the upstream source of the digest and the rotation procedure (source: threat model)
- Worker node labels (`node-role.fury.io/infra=true`) are for scheduling only — do not grant additional privileges through them (source: threat model)
- In `.zlab.yaml` port mappings, bind to `127.0.0.1` (loopback) only — never `0.0.0.0` — so Kind ports are not reachable from the LAN (source: threat model)
- Validate that zlab/Kind does not auto-mount `/var/run/docker.sock` into cluster nodes (source: threat model)
- Ensure kubeconfig is written with `0600` permissions and never `chmod 644` (source: threat model)

## Best Practices

- Error handling: `mise run up` must `set -euo pipefail`; fail fast if `zlab up` returns non-zero or control-plane does not reach Ready within 120s
- Naming: cluster name `fury-baobank` (matches repo); node names follow Kind defaults (`fury-baobank-control-plane`, `fury-baobank-worker`, `fury-baobank-worker2`)
- Style: no hardcoded K8s versions in multiple places — single source in `.zlab.yaml`
- Idempotency: re-running `mise run up` on an existing cluster must detect the cluster and skip create (use `kind get clusters | grep -q`)

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|---|---|---|
| Unit | N/A (config-only) | — |
| Integration | Verify `zlab up` produces 3 nodes, correct roles, kubeconfig permissions 0600 | Covered by SDD-004 BATS |
| E2E | Full `mise run up` → kubectl-ready cluster | Covered by SDD-004 BATS |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `.zlab.yaml` declares 3 nodes: 1 control-plane, 2 workers
- [ ] `cni: none` is set in the Kind config
- [ ] `kindest/node` image is pinned by `@sha256:` digest
- [ ] Port mappings use `listenAddress: 127.0.0.1`
- [ ] `mise run up` creates the cluster and labels worker nodes with `node-role.fury.io/infra=true`
- [ ] `mise run up` is idempotent — second invocation does not fail
- [ ] Kubeconfig at `~/.kube/config` has permissions `0600` after cluster creation
- [ ] Cluster context is named `kind-fury-baobank`

## Context / Contesto

- [ ] `labs/environments/ingress-full/.zlab.yaml` — reference pattern for Kind+zlab
- [ ] `labs/environments/ingress-full/mise.toml` — reference for `cluster-up` task idempotency
- [ ] `labs/_shared/scripts/wait-for-pods.sh` — helper for readiness waits
- [ ] `.forgia/fd/FD-001-kind-cluster-cilium.md` — parent FD
- [ ] `.forgia/fd/FD-001-threat-model.md` — security recommendations
- [ ] [Kind docs: configuring nodes](https://kind.sigs.k8s.io/docs/user/configuration/)

## Constitution Check

- [ ] Respects code standards (YAML 2-space indent, TOML compliant)
- [ ] Respects commit conventions (`feat(FD-001): scaffold Kind cluster config`)
- [ ] No hardcoded secrets (config contains no credentials)
- [ ] Tests defined in SDD-004 (E2E BATS), not here

---

## Work Log / Diario di Lavoro

### Agent / Agente

- **Executor**: claude-code
- **Started**: 2026-04-15
- **Completed**: 2026-04-15
- **Duration / Durata**: ~20 min

### Decisions / Decisioni

1. **Dropped zlab in favor of direct Kind config.** zlab v0.4.0 supports `cni: default | cilium | calico | flannel` but NOT `cni: none`. Since FD-001 requires Cilium to be installed via furyctl (not pre-installed by zlab), we need `disableDefaultCNI: true` in the Kind config. zlab does not expose this. Other Fury labs (`ingress-full`, `istio-full`) already use Kind directly — we follow the same pattern. The `.zlab.yaml` file was removed; cluster lifecycle is driven by `mise` + `kind` directly.

2. **Node image**: pinned to `kindest/node:v1.31.14@sha256:6f86cf509dbb42767b6e79debc3f2c32e4ee01386f0489b3b2be24b0a55aac2b` from the upstream Kind v0.31.0 release. Used upstream `kindest/node` (not `registry.sighup.io/fury/kindest/node`) to avoid an additional auth dependency for the lab. The registry mirror can be swapped in later without changing the digest.

3. **`kubeProxyMode: none`**: added to the Kind config since Cilium will replace kube-proxy (SDD-002). Declaring it here ensures Kind does not deploy a `kube-proxy` DaemonSet that would need to be deleted later.

4. **Infra labels applied post-cluster**: Kind does not support arbitrary node labels in its native config — labels are applied via `kubectl label` in the `mise run up` task after the cluster is created.

5. **Single port mapping for Hubble UI**: exposed on `127.0.0.1:31200` (loopback only) per threat model guidance. Additional mappings will be added by future SDDs as needed.

### Output

- **Commit(s)**: (pending)
- **PR**: N/A (direct commit to main)
- **Files created/modified**:
  - `cluster/kind.yaml` (created)
  - `mise.toml` (rewritten — tasks: up, down, status)
  - `.zlab.yaml` (removed — not compatible with `disableDefaultCNI`)

### Retrospective / Retrospettiva

- **What worked**: reusing the `ingress-full` lab pattern for Kind config + mise `set -euo pipefail` task gave a fast, copy-adaptable starting point. Idempotency via `kind get clusters | grep -q` is trivial and reliable.
- **What didn't**: assumption that zlab would support `cni: none` — it does not. The FD should have surfaced this earlier. For future FDs that touch zlab/Kind, check zlab's supported options before writing the SDD.
- **Suggestions for future FDs**:
  - Add a TD entry documenting "Kind directly (not zlab) when disableDefaultCNI is required"
  - Consider proposing `cni: none` support to zlab upstream — would simplify Fury labs that install CNI via furyctl
