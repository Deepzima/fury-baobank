# Changelog

## [FD-001] Kind multinode cluster with Cilium via furyctl — 2026-04-15

### Summary

Phase 0 infrastructure for fury-baobank: 3-node Kind cluster (1 control-plane + 2 infra workers) with Cilium CNI installed via furyctl using the KFD networking module. All 4 SDDs completed; 26/26 BATS tests pass.

### SDDs completed

- **SDD-001** Kind cluster config with role labels and `cni: none`
- **SDD-002** `furyctl.yaml` + customPatches for Cilium installation via KFD networking module
- **SDD-003** Hubble port-forward task, mTLS check script, starter query doc
- **SDD-004** Integration wiring + E2E BATS suite (26 cases across 6 files)

### Key decisions (aggregated from SDD Work Logs)

1. **Dropped zlab for Kind-directly** — zlab v0.4.0 does not expose `disableDefaultCNI`. Followed the pattern used by other Fury labs (`ingress-full`, `istio-full`).
2. **`KFDDistribution` over `Furyfile.yaml` legacy vendor** — cleaner, single source of module pinning.
3. **`customPatches` declarative for Cilium tweaks** — kube-proxy replacement, Hubble mTLS — instead of post-apply kubectl patches.
4. **Render script for dynamic IP** — the Kind control-plane IP is assigned at boot, so the `KUBERNETES_SERVICE_HOST` customPatch is generated just-in-time by `scripts/render-cilium-override.sh` before `furyctl apply`. Only non-declarative step; workaround pending upstream enhancement (NETWORKING-001, FURYCTL-002).
5. **Test fixes during verification**: replaced `busybox httpd` with `python -m http.server` (reliable HTTP), added `podAntiAffinity` to force node split, switched DNS probe from `nslookup` to `getent`.

### Upstream contribution candidates discovered

See [cncf/findings-fury-baobank.md](../../../../cncf/findings-fury-baobank.md) for the full list. Highlights:

- **NETWORKING-001**: Cilium `kube-proxy-replacement` chicken-and-egg on Kind — KFD networking module should expose `k8sServiceHost` in the Distribution schema.
- **FURYCTL-002**: no template/env substitution in customPatches — enhancement to let furyctl resolve dynamic values at apply time.
- **MISE-001**: mise Tera template conflicts with shell `{{...}}` — doc/option enhancement.
- Plus 4 more on zlab and furyctl (see findings doc).

### Files produced

- `cluster/kind.yaml`
- `furyctl.yaml`
- `manifests/overrides/cilium-kube-proxy-replacement.yaml`
- `scripts/render-cilium-override.sh`
- `scripts/hubble-mtls-check.sh`
- `docs/hubble-queries.md`
- `docs/ARCHITECTURE.md`
- `tests/helpers.bash` + 6 BATS suites (26 test cases)
- `mise.toml` with 8 tasks: `up`, `install-cni`, `hubble`, `hubble-mtls-check`, `test`, `all`, `down`, `status`

### Retrospective (what worked / what didn't)

**Worked**
- Separating validation (BATS) from provisioning (mise tasks) — failures are easy to localize.
- Using the schema (`kfddistribution-kfd-v1alpha2.json`) to discover what's possible instead of guessing.
- `mise run all` as single-command validation path.
- Pinning `kindest/node` by SHA digest upfront — avoids surprises on upgrades.

**Didn't**
- First run assumed `furyctl apply` would succeed and that a post-apply patch would be enough. Actually furyctl waits for readiness → chicken-and-egg stall.
- Initial render patch only covered `cilium-agent` → missed the init container `config` and the separate `cilium-operator` Deployment. Three restarts to get it right.
- `mise run all` with `depends = ["up","install-cni","test"]` ran tasks in parallel — had to switch to chained `depends` on `test → install-cni → up`.
- First BATS pass had 3 failures from test-quality issues (jsonpath, readinessProbe misconfig, missing anti-affinity) — not cluster issues. Lesson: run BATS against a known-good cluster before wiring them into CI.

### Next step

FD-002 — install Bank-Vaults Operator + Webhook on this cluster. Phase 1 of fury-baobank.
