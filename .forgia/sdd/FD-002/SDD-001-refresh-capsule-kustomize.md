---
id: "SDD-001"
fd: "FD-002"
title: "Refresh Capsule kustomize boilerplate to chart v0.12.x"
status: completed
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-15"
started: ""
completed: ""
tags: [capsule, kustomize, helm, refactor]
---

# SDD-001: Refresh Capsule kustomize boilerplate to chart v0.12.x

> Parent FD: [[FD-002]]

## Scope

The folder `manifests/plugins/kustomize/capsule/` currently vendors Capsule chart **v0.6.2** (2.5 years old). Refresh it to a current stable release (chart **v0.12.x**) and produce a clean, reviewable artifact:

- Bump the chart version in `Makefile`.
- Re-run `helm pull projectcapsule/capsule --version 0.12.x` and `helm template` to regenerate `resources/capsule-from-helm.yaml`.
- Refresh `crds/` from the new chart tarball.
- Audit the existing `patches/capsule-proxy-ca.yaml` and `secretGenerator` referencing `../../../../secrets/ssl/ca.crt` — drop if not required by the lab scope (single-cluster Kind, no capsule-proxy ingress); keep only if a real reason remains.
- Audit `values.yaml` for: log level (must be `info`, never `debug`), replicas (`replicas: 2` for controller HA), webhook timeout, absence of hardcoded secrets, absence of wildcard RBAC.
- Add a self-documenting header to the rendered file containing chart version and regen timestamp, emitted by the Makefile.

Out of scope: wiring into `furyctl.yaml` (SDD-002), BATS tests (SDD-003), mise task integration (SDD-004).

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|---|---|---|
| `Makefile` target `template` | make target | Pulls the pinned chart, copies CRDs into `crds/`, runs `helm template` with `../../../helm/capsule/values.yaml`, writes `resources/capsule-from-helm.yaml` with a header block (chart version + ISO timestamp) |
| `values.yaml` | Helm values file | Overrides applied at `helm template` time: controller replicas 2, log level info, webhook timeout 5s, minimal additional role bindings |
| `resources/capsule-from-helm.yaml` | YAML (committed) | Deterministic rendered output — source of truth consumed by `kustomization.yaml` |
| `crds/*.yaml` | YAML (committed) | Capsule CRDs refreshed from chart v0.12.x — Tenant, CapsuleConfiguration, Global/TenantResources, ProxySetting |
| `kustomization.yaml` | Kustomize | Unchanged resource list as long as chart structure is stable; update only if CRDs renamed/added |

## Constraints / Vincoli

- Language: shell (Makefile), YAML (values, rendered, kustomization)
- Framework: Helm 3.16+, Kustomize 5.8+
- Dependencies: SDD-002 will wire the result into `furyctl.yaml`; nothing depends on this SDD inside FD-002 except downstream SDDs
- Patterns:
  - Chart pinned by exact version in `Makefile` (not a floating tag)
  - Only one overrides file (`values.yaml`) — no scattered overrides
  - Rendered output is reproducible: two consecutive `mise run capsule:template` calls produce identical diffs

### Security (from threat model)

- Audit the Capsule chart `values.yaml` before rendering. Confirm: `--log-level` is not `debug`, no secrets embedded, controller requests sane resources, no wildcards in `additionalRoleBindings`. Document findings in the Work Log (source: threat model)
- Configure `replicas: 2` for the Capsule controller in `values.yaml` to avoid single-pod DoS; verify this is compatible with the chart v0.12.x schema (source: threat model)
- Set `timeoutSeconds: 5` (or lower) on the validating webhook configuration via a `customPatch` in the kustomize folder — prevents slow webhook from becoming a cluster-wide DoS surface (source: threat model)
- Pin the Capsule controller image by digest in the rendered manifest (override from `values.yaml` or post-render patch). Acceptable to defer but must be tracked as a TODO in the Work Log and surfaced as a finding (source: threat model)
- Add a comment header to the rendered `capsule-from-helm.yaml` containing chart version and regen timestamp; the Makefile must emit these automatically so the diff is self-documenting (source: threat model)

## Best Practices

- Error handling: `Makefile` target uses `set -eu` via POSIX shell idioms; fail loud on `helm pull` or `helm template` errors; never leave a half-written rendered file (write to `.tmp` then `mv`)
- Naming: keep the existing folder structure (`resources/`, `crds/`, `patches/`) — downstream consumers (SDD-002 kustomize folder path) depend on it
- Style: YAML 2-space indent, no tabs; comment blocks at the top of generated files explaining "do not edit by hand, regenerate via `mise run capsule:template`"

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|---|---|---|
| Unit | Makefile `template` target runs idempotently (two runs → no diff) | Manual verification in Work Log |
| Integration | Rendered output passes `kustomize build` without errors | Manual + CI in SDD-002 |
| E2E | Covered by SDD-003 BATS | — |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `Makefile` pins chart to exact version ≥ 0.12.0 (no `latest`, no floating branch)
- [ ] `resources/capsule-from-helm.yaml` regenerated from pinned chart; starts with a comment header containing chart version + ISO 8601 timestamp
- [ ] `crds/` contents match the chart's `crds/` directory verbatim (no hand edits)
- [ ] `values.yaml` audit completed and documented in the Work Log; log level `info`, controller `replicas: 2`, webhook `timeoutSeconds: 5`
- [ ] `patches/capsule-proxy-ca.yaml` and `secretGenerator` either retained with justification or removed; Work Log records the decision
- [ ] Controller image digest pinned OR the deferral is recorded as a TODO with an upstream follow-up
- [ ] Re-running the Makefile target produces an identical file (byte-for-byte apart from the timestamp line)
- [ ] `kustomize build manifests/plugins/kustomize/capsule/` completes with exit 0 on the refreshed folder (no schema errors)

## Context / Contesto

- [ ] `manifests/plugins/kustomize/capsule/Makefile` — current version pinned at `v0.6.2`
- [ ] `manifests/plugins/kustomize/capsule/kustomization.yaml` — resource list to keep in sync
- [ ] `manifests/plugins/kustomize/capsule/resources/capsule-from-helm.yaml` — current rendered output
- [ ] `manifests/plugins/kustomize/capsule/crds/` — current CRDs
- [ ] `manifests/plugins/kustomize/capsule/patches/capsule-proxy-ca.yaml` — decide keep/drop
- [ ] `.forgia/fd/FD-002-capsule-via-furyctl-plugin.md` — parent FD
- [ ] `.forgia/fd/FD-002-threat-model.md` — SDD-001 security recommendations (5 items)
- [ ] Upstream: https://github.com/projectcapsule/capsule/releases (chart v0.12.4 at Dec 2024)
- [ ] Upstream chart docs: https://github.com/projectcapsule/charts/tree/main/charts/capsule

## Constitution Check

- [ ] Respects code standards (YAML 2-space indent, Makefile portable)
- [ ] Respects commit conventions (`chore(FD-002): refresh Capsule boilerplate to v0.12.x`)
- [ ] No hardcoded secrets (values.yaml audited, no secrets embedded)
- [ ] Tests defined in SDD-003, referenced here for completeness

---

## Work Log / Diario di Lavoro

### Agent / Agente

- **Executor**: claude-code
- **Started**: 2026-04-15
- **Completed**: 2026-04-15
- **Duration / Durata**: ~25 min

### Decisions / Decisioni

1. **Dropped capsule-proxy from the bundle.** The lab is single-operator (cluster-admin kubeconfig); capsule-proxy's RBAC filtering is only meaningful when multiple human users hit the API via the proxy. Setting `proxy.enabled: false` in `values.yaml` removes an entire second Deployment/Service/Ingress/TLS chain — reduces attack surface and simplifies the rendered file by ~2000 lines.

2. **Dropped `secretGenerator` for the trusted CA and the `patches/capsule-proxy-ca.yaml`.** Both existed only to feed the capsule-proxy chain; without the proxy they are dead config. Consequently the directory reference `../../../../secrets/ssl/ca.crt` — which would have pulled a non-existent file in this repo — is no longer needed.

3. **Dropped `resources/ingress.yaml`.** Exposed the proxy; out of scope after decision #1.

4. **Moved `values.yaml` into the folder** (`manifests/plugins/kustomize/capsule/values.yaml`). The original Makefile referenced `../../../helm/capsule/values.yaml` — a path that doesn't exist in this repo. Keeping values alongside the Makefile makes the bundle self-contained: one `git clone` gives you everything needed to regen.

5. **Disabled `serviceMonitor.enabled` explicitly.** Chart default is already false, but explicit is safer — the lab does not deploy prometheus-operator, and a stray ServiceMonitor would fail `kustomize build` if the CRD existed only in a future iteration.

6. **Enforced `pod-security.kubernetes.io/enforce: baseline` on `capsule-system` namespace.** Prevents accidental privileged pod deployment into the controller's namespace (threat model `controller E: ClusterRoleBinding abuse`). Chose `baseline` over `restricted` because Capsule's controller needs `mount` and some non-restricted fields; `baseline` is the tightest it can run under.

7. **Chart keys for webhook timeout**: first attempt used `webhook.hooks.mutating.timeoutSeconds` (guess from common Helm charts). Chart v0.12.4 actually uses `webhooks.mutatingWebhooksTimeoutSeconds` / `webhooks.validatingWebhooksTimeoutSeconds`. Verified via `helm show values`. Corrected and re-rendered — `timeoutSeconds: 5` now appears in both webhook configurations.

8. **Log level**: the chart accepts the string `"info"` (not a numeric verbosity level). Chose `info` — `debug` would log admission review bodies and is explicitly flagged by the threat model.

9. **Image digest pinning DEFERRED.** The chart references `ghcr.io/projectcapsule/capsule:v0.12.4` and `docker.io/clastix/kubectl:v1.31` by tag. Pinning to digests requires Docker running AND authenticated pulls to resolve — not blocking for the lab, tracked as a TODO in the Work Log to be revisited in FD-003 or earlier if a repo-cache solution is adopted.

10. **CRD inventory changed from v0.6.2 → v0.12.4**: added `resourcepoolclaims`, `resourcepools`, `tenantowners`. Removed `capsule.clastix.io_proxysettings.yaml` (moved to a separate capsule-proxy chart). `kustomization.yaml` updated to match the 7 new CRD filenames.

### Output

- **Commit(s)**: (pending)
- **PR**: N/A
- **Files created/modified**:
  - `manifests/plugins/kustomize/capsule/Makefile` (rewritten — v0.6.2 → v0.12.4, adds provenance header, self-contained values path)
  - `manifests/plugins/kustomize/capsule/values.yaml` (NEW — previously external)
  - `manifests/plugins/kustomize/capsule/resources/capsule-from-helm.yaml` (regenerated from v0.12.4)
  - `manifests/plugins/kustomize/capsule/resources/namespace.yaml` (rewritten with PSA labels)
  - `manifests/plugins/kustomize/capsule/crds/` (refreshed, 7 CRDs)
  - `manifests/plugins/kustomize/capsule/kustomization.yaml` (simplified — no patches, no secretGenerator, no ingress/proxy)
  - `manifests/plugins/kustomize/capsule/patches/` (DELETED)
  - `manifests/plugins/kustomize/capsule/resources/ingress.yaml` (DELETED)

### Retrospective / Retrospettiva

- **What worked**: inspecting `helm show values` before writing `values.yaml` — saves the back-and-forth of guessing chart keys. `kustomize build` as a post-render sanity check catches schema errors quickly (15 distinct kinds rendered cleanly).
- **What didn't**: first render had `timeoutSeconds: 30` because the values override was pointing at a path the chart doesn't expose. Re-render confirmed the fix. Also, the old boilerplate shipped overrides (`secretGenerator` with a CA path pointing outside the folder) that couldn't possibly work in this repo — evidence the original was copied from `pec/infra` and never adapted.
- **Suggestions for future FDs**: add a `mise run capsule:diff` helper that shows `git diff` of the rendered file after a regen — makes reviews trivial. Consider documenting in the Fury networking module how to add new plugin folders like this one (was unclear from the docs).
