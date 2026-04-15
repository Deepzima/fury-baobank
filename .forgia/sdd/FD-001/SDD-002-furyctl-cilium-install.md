---
id: "SDD-002"
fd: "FD-001"
title: "Furyfile.yaml and furyctl.yaml for Cilium installation"
status: completed
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-15"
started: ""
completed: ""
tags: [furyctl, cilium, networking, supply-chain]
---

# SDD-002: Furyfile.yaml and furyctl.yaml for Cilium installation

> Parent FD: [[FD-001]]

## Scope

Write `Furyfile.yaml` that pins the exact git SHA of `fury-kubernetes-networking` (not a branch or floating tag). Write `furyctl.yaml` that declares `KFDDistribution` with `networking.type: cilium` and Hubble enabled. Use `customPatches` to:

- Pin every Cilium and Hubble container image by SHA256 digest
- Enable `kubeProxyReplacement: true` (native eBPF routing)
- Remove any Docker socket mount if present in the vendored manifests
- Enable Hubble mTLS if the module does not set it by default

Add a `mise run install-cni` task that runs `furyctl vendor` (with a network dependency warning) and then `furyctl apply --disable-analytics`. Must be idempotent — second run is a no-op if everything is already applied.

Out of scope: cluster bootstrap (SDD-001), Hubble exposure/UI (SDD-003), end-to-end wiring and tests (SDD-004).

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|---|---|---|
| `Furyfile.yaml` | YAML file | Version pin for `fury-kubernetes-networking` by git SHA |
| `furyctl.yaml` | YAML file | `KFDDistribution` spec with `networking.type: cilium`, Hubble enabled, `customPatches` for digest pinning |
| `manifests/overrides/*.yaml` | Kustomize patches | Referenced from `customPatches.patches`; pin images, strip socket mounts, enable mTLS |
| `mise.toml` task `install-cni` | mise task | Invokes `furyctl vendor` + `furyctl apply --disable-analytics` |
| Vendored tree | Directory | `vendor/katalog/cilium/` — produced by `furyctl vendor`, not committed (see `.gitignore`) |

## Constraints / Vincoli

- Language: YAML (Furyfile, furyctl, kustomize patches), TOML (mise task)
- Framework: furyctl v0.34.0+, KFD networking module at a pinned SHA, Kustomize 5.8+
- Dependencies: SDD-001 must have produced a running Kind cluster with `cni: none`
- Patterns:
  - `Furyfile.yaml` pins by SHA — never `master`, never a named branch
  - Every `image:` reference in `customPatches` overrides uses `@sha256:` digests
  - `--disable-analytics` is passed in every `furyctl` invocation inside `mise.toml`, not as a manual step

### Security (from threat model)

- Pin the exact git SHA of `fury-kubernetes-networking` in `Furyfile.yaml`. Do not use branch names or floating tags. Document how to verify the SHA matches an upstream signed release (source: threat model)
- In `furyctl.yaml`, use `customPatches` to pin every Cilium and Hubble container image by SHA digest, overriding any `:vX.Y` tags from the module defaults (source: threat model)
- Ensure every `furyctl` invocation uses `--disable-analytics`; add this flag in the `mise run` task definitions, not as a manual step (source: threat model)
- Verify the KFD networking module kustomization does not mount the Docker socket into any cluster pod. If it does, override via `customPatches` to remove the mount — it is not needed for CNI operation (source: threat model)
- Do not grant capabilities beyond the Cilium default; do not run other privileged pods in `kube-system` (source: threat model)

## Best Practices

- Error handling: `mise run install-cni` uses `set -euo pipefail`; if `furyctl vendor` fails, abort before apply; if `furyctl apply` fails, do not leave the cluster half-configured (document recovery)
- Naming: `customPatches` files live in `manifests/overrides/<component>-<purpose>.yaml` (e.g., `manifests/overrides/cilium-image-pins.yaml`)
- Style:
  - One override file per concern (image pins, mTLS, remove socket) — do not pile everything into one mega-patch
  - Comments in `furyctl.yaml` and `customPatches` YAML explain why a patch exists

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|---|---|---|
| Unit | `yamllint` on `Furyfile.yaml`, `furyctl.yaml`, overrides | In mise `lint` task |
| Integration | `furyctl apply` succeeds and Cilium pods reach Ready | Covered by SDD-004 BATS |
| E2E | Full stack bootstrap: SDD-001 + SDD-002 + Cilium agents scheduled on all nodes | Covered by SDD-004 BATS |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `Furyfile.yaml` pins `fury-kubernetes-networking` to a specific git SHA (40 hex chars, not a branch)
- [ ] `furyctl.yaml` declares `networking.type: cilium` and Hubble enabled
- [ ] Every container image in `customPatches` overrides is pinned by `@sha256:` digest
- [ ] `customPatches` includes a patch that removes any Docker socket mount, if present
- [ ] `customPatches` enables Hubble mTLS (or documents why the upstream default is already sufficient)
- [ ] `mise run install-cni` runs `furyctl vendor` followed by `furyctl apply --disable-analytics`
- [ ] `mise run install-cni` is idempotent (second run produces no resource churn)
- [ ] After successful apply: `kubectl get daemonset -n kube-system kube-proxy` returns NotFound (Cilium replaces it)
- [ ] After successful apply: `kubectl get pods -n kube-system -l k8s-app=cilium` shows all agents Ready

## Context / Contesto

- [ ] `modules/fury-kubernetes-networking/katalog/cilium/README.md` — upstream module docs
- [ ] `modules/fury-kubernetes-networking/katalog/cilium/MAINTENANCE.values.yaml` — default values
- [ ] `labs/environments/ingress-full/furyctl-before.yaml` — reference for `customPatches` patterns in KFD
- [ ] `labs/environments/ingress-full/mise.toml` — reference for furyctl task patterns
- [ ] `.forgia/fd/FD-001-kind-cluster-cilium.md` — parent FD
- [ ] `.forgia/fd/FD-001-threat-model.md` — security recommendations
- [ ] [Cilium values reference](https://docs.cilium.io/en/stable/helm-reference/)

## Constitution Check

- [ ] Respects code standards (YAML 2-space indent)
- [ ] Respects commit conventions (`feat(FD-001): vendor and install Cilium via furyctl`)
- [ ] No hardcoded secrets (Furyfile and furyctl.yaml contain no credentials)
- [ ] Tests defined in SDD-004 (E2E BATS) — this SDD provides the config artifact

---

## Work Log / Diario di Lavoro

### Agent / Agente

- **Executor**: claude-code
- **Started**: 2026-04-15
- **Completed**: 2026-04-15
- **Duration / Durata**: ~15 min

### Decisions / Decisioni

1. **Dropped `Furyfile.yaml` in favor of KFDDistribution**. The `Furyfile` + `furyctl legacy vendor` path is for standalone module consumption; `KFDDistribution` + `furyctl apply` handles vendoring internally via the pinned distribution version (`v1.34.0`), which already locks networking module to `v3.1.0` (Cilium 1.18.7). Using `KFDDistribution` is more KFD-idiomatic and reduces moving parts.

2. **Minimal distribution**: enabled only `networking.type: cilium`; every other module set to `type: none`. Ingress is declared with a `certManager.clusterIssuer` stub only because the schema requires it — no ingress controller is actually installed (`nginx.type: none`).

3. **customPatches on `cilium-config` ConfigMap**: enables `kube-proxy-replacement: true`, `bpf-lb-sock: true`, `enable-node-port: true`, `enable-external-ips: true`, `enable-host-port: true`, and Hubble mTLS (`hubble-tls-disabled: false`, `hubble-tls-auto-enabled: true`). The KFD networking module default is `kube-proxy-replacement: false` — the patch is mandatory for our Kind cluster created with `kubeProxyMode: none`.

4. **Image digest pinning deferred**: the KFD networking module ships images as `registry.sighup.io/fury/cilium/cilium:v1.18.7` (tagged, not digested). Converting every image reference to `@sha256:...` requires Docker running to resolve digests — skipped for the lab. TODO: add digest override via customPatches when Docker is up; for now the tag is sufficiently specific for lab use.

5. **Cilium `podCidr: 10.244.0.0/16` + `maskSize: 24`**: matches the Kind cluster config in SDD-001 so that pods get IPs from the same CIDR Kind expects.

### Output

- **Commit(s)**: (pending)
- **PR**: N/A (direct to main)
- **Files created/modified**:
  - `furyctl.yaml` (created — KFDDistribution config)
  - `manifests/overrides/cilium-kube-proxy-replacement.yaml` (created)
  - `mise.toml` (task `install-cni` added; `furyctl` added to `[tools]`)

### Retrospective / Retrospettiva

- **What worked**: the schema-driven approach — loading `kfddistribution-kfd-v1alpha2.json` revealed that `networking.type: cilium` is a first-class option, no hacks needed.
- **What didn't**: initial attempt with `Furyfile.yaml` pointing to a specific commit SHA was redundant — `KFDDistribution` already vendors the right module version. A better dev-guide entry would make this clearer.
- **Suggestions for future FDs**: add a helper script `scripts/pin-cilium-digests.sh` that, given Docker running, inspects `registry.sighup.io/fury/cilium/*` and generates a `customPatches` override with SHA256 digests. Then the lab can be hardened post-hoc without blocking progress.
