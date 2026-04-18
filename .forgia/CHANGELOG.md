# Changelog

## [FD-003] OpenBao per-tenant secret management via Bank-Vaults operator — 2026-04-18

### Summary

OpenBao-as-a-Service validated: Bank-Vaults operator v1.23.4 + webhook v1.22.2 deployed as furyctl kustomize plugins. Per-tenant architecture — each Capsule tenant gets a dedicated OpenBao instance (`reevo-ob-id-<name>`) with its own Raft storage, unseal keys, KV-v2, and Kubernetes auth. All 5 SDDs completed; 59/59 BATS pass (40 FD-001/002 + 19 FD-003).

### SDDs completed

- **SDD-001** Bank-Vaults operator kustomize plugin (OCI chart render, CRD, log level patch debug→info)
- **SDD-002** Bank-Vaults webhook kustomize plugin (cert-manager two-tier CA — no isCA patch needed unlike Capsule)
- **SDD-003** Per-tenant OpenBao provisioning (Vault CR template, 2 test tenants, RBAC for sidecar)
- **SDD-004** 19-case BATS suite (control plane + per-tenant + 5 cross-tenant isolation tests)
- **SDD-005** Integration wiring (furyctl.yaml + mise bank-vaults:template + 05-security.bats extended)

### Key decisions

1. **OpenBao paths `/openbao/config` + `/openbao/data`** — the OpenBao image uses different paths than HashiCorp Vault (`/vault/`). Required explicit `vaultContainerSpec` with correct mountPaths. Undocumented in Bank-Vaults — discovered via crash debugging.
2. **ServiceAccount `default` + explicit RBAC** — the operator does NOT create a ServiceAccount or RBAC for the bank-vaults sidecar. The sidecar needs `get/create/update` on Secrets for unseal keys. Created `tenant-vault-rbac-template.yaml` applied per-tenant.
3. **Operator log level patched debug→info** — chart hardcodes `OPERATOR_LOG_LEVEL=debug` with no values.yaml key. Debug logs may contain unseal keys across tenant instances. Patched via kustomize strategic merge.
4. **kapp strips `app.kubernetes.io/*` labels** — all BATS tests use name-based selectors instead of label selectors (same issue as Capsule FD-002).
5. **Configurer needs 30-60s after unseal** — `setup_file` waits for `vault policy list | grep admin` (not just `secrets list`) to confirm full externalConfig reconciliation.
6. **Audit log at `/tmp/audit.log`** — OpenBao runs as non-root, `/vault/logs/` does not exist in the image. `/tmp/` is writable.
7. **OCI chart registry** — Bank-Vaults moved from `kubernetes-charts.banzaicloud.com` (dead) to `oci://ghcr.io/bank-vaults/helm-charts/`. No `helm repo add` needed.
8. **Webhook has proper two-tier CA** — unlike Capsule, the webhook chart ships SelfSigned Issuer → CA Certificate (`isCA: true`) → CA Issuer → leaf. No patch needed.

### Upstream findings

- **BANK-VAULTS-001**: operator does not create ServiceAccount or RBAC for the bank-vaults sidecar — every user must manually create a Role/RoleBinding for Secret access in the Vault namespace.
- **BANK-VAULTS-002**: `OPERATOR_LOG_LEVEL=debug` hardcoded in the Deployment template with no values.yaml override. Security concern for multi-tenant deployments.
- **BANK-VAULTS-003**: no documentation for OpenBao path differences (`/openbao/` vs `/vault/`). Community example in bank-vaults/bank-vaults#3543 uses wrong paths.

---

## [FD-002] Capsule multi-tenancy via furyctl kustomize plugin — 2026-04-17

### Summary

Phase 1 prep: Capsule v0.12.4 deployed via `plugins.kustomize` in the same `furyctl apply` pass that installs Cilium. Chart refreshed from v0.6.2 (2.5-year-old boilerplate) to current stable. All 4 SDDs completed; fresh-cluster `mise run all` passes 38/38 BATS (26 from FD-001 + 12 new from FD-002).

### SDDs completed

- **SDD-001** Kustomize boilerplate refresh (chart v0.6.2 → v0.12.4, dropped capsule-proxy + ServiceMonitor + CA secretGenerator)
- **SDD-002** `furyctl.yaml` `plugins.kustomize` entry (single folder, idempotent with Cilium)
- **SDD-003** 10-case BATS suite (`tests/06-capsule.bats`) covering install + webhook + Tenant enforcement + privilege-escalation rejection
- **SDD-004** `capsule:template` regen task + context guard + 2 extra security assertions in `tests/05-security.bats`

### Key decisions (aggregated from SDD Work Logs)

1. **cert-manager delegation, not Capsule self-gen** — `manager.options.generateCertificates: false` + `certManager.generateCertificates: true`. With `replicaCount: 2`, only the leader can generate the cert; non-leader pods crashloop until leader wins. Cert-manager removes the race.
2. **System-namespace exemption for the `namespaces` webhook** — `namespaceSelector NotIn [capsule-system, kube-system, kube-public, kube-node-lease, cert-manager, local-path-storage]` avoids the bootstrap chicken-and-egg where the webhook blocks creation of the namespace that hosts it.
3. **`isCA: true` kustomize patch on the webhook Certificate** — upstream chart omits it; without CA:TRUE + keyCertSign, Go strict x509 verification rejects the injected caBundle with "parent certificate cannot sign this kind of certificate". Patch is the minimal viable fix; candidate for upstream PR (see findings).
4. **No capsule-proxy in Phase 0–1** — proxy is only needed for multi-tenant RBAC filtering for UI/kubectl users; the lab uses cluster-admin kubeconfig (single operator). Proxy adds Deployment+Service+Ingress+TLS without validating anything new.
5. **No ServiceMonitor** — lab has no Prometheus; chart default would fail (CRD missing).
6. **Tenant status polling with `wait_for 30`** — webhook-accepted ≠ reconciled. Controller typically sets `status.state=Active` within 1–2s; 30s covers slow CI.
7. **`auth can-i` exit code semantics in BATS** — `-q` answer "no" returns exit 1; the PASS assertion is `$status -eq 1`.

### Upstream contribution candidates discovered

- **CAPSULE-001**: chart's `certManager.generateCertificates: true` produces a Certificate without `isCA: true`, so the resulting leaf cert can't serve as its own CA bundle under strict x509. Proposed fix: either default `isCA: true` or ship a two-tier Issuer pattern (SelfSigned → CA Certificate → CA Issuer → webhook leaf).
- **CAPSULE-002**: default `webhooks.hooks.namespaces.namespaceSelector` should exempt `capsule-system` + core system namespaces out of the box — everyone hits the bootstrap chicken-and-egg on first install.

### Aggregate retrospective

**What worked across SDDs:**
- `helm show values` before writing `values.yaml` (SDD-001) — avoids guessing chart keys
- `kustomize build` as post-render sanity (SDD-001) — catches schema errors before `furyctl apply`
- 2-line `furyctl.yaml` diff (SDD-002) — easy to review, no speculative changes
- `setup_file` fail-fast pattern (SDD-003) — immediate actionable errors instead of 9 cascading failures
- `bats --count` as cheap structural check (SDD-004) — verifies test count before running full suite

**What didn't work / lessons:**
- Old boilerplate had `secretGenerator` pointing outside the folder — evidence of unvalidated copy from `pec/infra` (SDD-001)
- `kubectl auth can-i --as owner` too indirect for privilege escalation testing — inspecting ClusterRoleBinding directly catches the exact threat (SDD-003)
- Context guard `*"fury-baobank"*` glob was too loose — `fury-baobank-staging` would pass. Tightened to exact-match `kind-${CLUSTER_NAME}` (SDD-004)

**Suggestions for future FDs:**
- `mise run capsule:diff` helper to show `git diff` of rendered chart after regen (SDD-001)
- `tests/helpers.bash` `fail_fast_if_missing` function to reduce boilerplate across suites (SDD-003)
- `tests/_common/context_guard.bash` helper sourced by all BATS files (SDD-004)

### Files changed

- `furyctl.yaml` — single `plugins.kustomize` entry for Capsule
- `mise.toml` — new `capsule:template` task, context guard in `all`
- `manifests/plugins/kustomize/capsule/` — full rewrite (Makefile, kustomization.yaml, values.yaml, rendered chart, CRDs, isCA patch, namespace with PSA labels)
- `tests/05-security.bats` — 2 new Capsule webhook assertions
- `tests/06-capsule.bats` — new (10 cases)
- `.forgia/fd/FD-002-*.md`, `.forgia/sdd/FD-002/SDD-00{1..4}-*.md`, `.forgia/fd/FD-002-threat-model.md` — full spec set

---

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
