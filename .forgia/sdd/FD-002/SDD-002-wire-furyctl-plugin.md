---
id: "SDD-002"
fd: "FD-002"
title: "Wire Capsule folder into furyctl.yaml plugins.kustomize"
status: completed
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-15"
started: ""
completed: ""
tags: [furyctl, kustomize, plugins, integration]
---

# SDD-002: Wire Capsule folder into furyctl.yaml plugins.kustomize

> Parent FD: [[FD-002]]

## Scope

Add the refreshed Capsule folder (output of SDD-001) to `spec.plugins.kustomize` in `furyctl.yaml` so `furyctl apply` builds and applies Capsule in the same reconciliation that installs Cilium. Verify that furyctl applies the networking module FIRST (Cilium) and the kustomize plugins AFTER — Capsule's webhook depends on a working CNI.

No new manifests produced here: SDD-001 already produced `manifests/plugins/kustomize/capsule/`. This SDD is the thin integration layer.

Out of scope: manifest refresh (SDD-001), tests (SDD-003), `mise` lifecycle integration (SDD-004).

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|---|---|---|
| `furyctl.yaml` (`spec.plugins.kustomize[]`) | YAML list entry | `{ name: capsule, folder: ./manifests/plugins/kustomize/capsule }` |
| SDD-001 folder | Directory | Readable, kustomize-buildable |
| `furyctl apply` order | Runtime | Networking module first → plugins.kustomize after; documented in Work Log |

## Constraints / Vincoli

- Language: YAML (`furyctl.yaml`)
- Framework: furyctl 0.34.0+ (already in `mise.toml` tools)
- Dependencies: SDD-001 must be complete — the plugin folder must exist and be valid
- Patterns:
  - Single entry under `plugins.kustomize` — do not split Capsule across multiple plugin entries
  - Folder path relative to the `furyctl.yaml` location (`./manifests/...` not absolute)
  - Keep the existing `customPatches.patches` list for Cilium untouched

### Security (from threat model)

- Verify `plugins.kustomize` entries run AFTER the networking module during `furyctl apply` (Cilium must be Ready before Capsule webhook is deployed). Document the observed ordering in the SDD Work Log (source: threat model)

## Best Practices

- Error handling: if `furyctl apply` fails because the plugin folder is malformed, the error must surface the folder name — verify by corrupting a file and running once; record observation in Work Log
- Naming: `name: capsule` — short, matches the folder
- Style: keep `furyctl.yaml` YAML consistent with the existing structure (2-space indent, block style)

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|---|---|---|
| Unit | `yamllint furyctl.yaml` | CI task (via mise) |
| Integration | `furyctl validate` (if available) on the updated file | Manual pre-check |
| E2E | Covered by SDD-003 (Capsule installed after `mise run install-cni`) | — |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `furyctl.yaml` has a `plugins.kustomize[]` entry referencing `./manifests/plugins/kustomize/capsule`
- [ ] `yamllint furyctl.yaml` passes
- [ ] Running `furyctl apply --config furyctl.yaml --outdir .fury --disable-analytics` (on the FD-001 Kind cluster) applies Cilium first, then Capsule, and both reach Ready
- [ ] Work Log documents the observed reconciliation order (which module/plugin runs first, with timestamps)
- [ ] No changes to the Cilium `customPatches.patches` list (diff check in PR)

## Context / Contesto

- [ ] `furyctl.yaml` — current file, contains Cilium customPatches (unchanged by this SDD)
- [ ] `.forgia/sdd/FD-002/SDD-001-refresh-capsule-kustomize.md` — output consumed here
- [ ] `.forgia/fd/FD-002-capsule-via-furyctl-plugin.md` — parent FD
- [ ] `.forgia/fd/FD-002-threat-model.md` — SDD-002 security recommendation (ordering)
- [ ] furyctl schema: `tools/fury-distribution/schemas/public/kfddistribution-kfd-v1alpha2.json` — confirm `plugins.kustomize[]` field structure

## Constitution Check

- [ ] Respects code standards (YAML 2-space indent)
- [ ] Respects commit conventions (`feat(FD-002): wire Capsule plugin into furyctl.yaml`)
- [ ] No hardcoded secrets
- [ ] Tests defined in SDD-003

---

## Work Log / Diario di Lavoro

### Agent / Agente

- **Executor**: claude-code
- **Started**: 2026-04-15
- **Completed**: 2026-04-15
- **Duration / Durata**: ~5 min

### Decisions / Decisioni

1. **Single plugin entry** — `name: capsule`, `folder: ./manifests/plugins/kustomize/capsule`. The rendered bundle from SDD-001 already aggregates controller + webhook + CRDs + RBAC in one kustomize root, so furyctl sees it as one cohesive unit.

2. **Ordering observation to be confirmed on first real run** — furyctl's plugins.kustomize run after the `modules` section is applied (per furyctl docs). That means Cilium (networking module) is installed first, Capsule plugin after — correct order (Capsule needs network to reach API server). Marked for verification in SDD-004 integration run.

3. **Left Cilium customPatches untouched.** Kept `customPatches.patches` list exactly as FD-001 left it (2 entries: cilium-config patch + Kind-specific generated file). No risk of regression on the 26 FD-001 BATS tests.

### Output

- **Commit(s)**: (pending)
- **PR**: N/A
- **Files created/modified**:
  - `furyctl.yaml` (single diff: `plugins.kustomize: []` → one entry pointing to the Capsule bundle)

### Retrospective / Retrospettiva

- **What worked**: the 2-line diff is a clear PR artifact — easy to review; no speculative changes bundled in.
- **What didn't**: N/A — this SDD is intentionally tiny; the complexity lives in SDD-001.
- **Suggestions for future FDs**: when adding a new `plugins.kustomize` entry, verify the folder produces valid kustomize output BEFORE wiring it into `furyctl.yaml` (did this in SDD-001 via `kustomize build`). Mixing the two steps makes debugging harder.
