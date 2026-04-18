---
id: "SDD-002"
fd: "FD-004"
title: "AppRole auth provisioning on baobank"
status: assigned
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-18"
started: ""
completed: ""
tags: [approle, auth, provisioning]
---

# SDD-002: AppRole auth provisioning on baobank

> Parent FD: [[FD-004]]

## Scope

Enable AppRole auth method on the test tenant's OpenBao instance (on baobank) and provision credentials for cross-cluster consumption. This is the bridge between the baobank platform and external consumers.

Deliverables:

1. **Provisioning script**: `scenarios/scen-secret-inject/scripts/provision-approle.sh` — automates all AppRole setup via the `vault` CLI (exec into the OpenBao pod or use port-forward).
2. The script performs:
   - Enable `approle` auth method at `auth/approle`
   - Create policy `consumer-app-policy` scoped to `secret/data/acme/*` (read-only)
   - Create AppRole `consumer-app` bound to the policy, with `secret_id_ttl=24h` and `token_ttl=1h`
   - Generate `role_id` and `secret_id`
   - Write test secret: `vault kv put secret/acme/db password=s3cret`
   - Output `role_id` and `secret_id` to stdout (consumed by SDD-003 for K8s Secret creation)
3. The script must be **idempotent** — safe to run multiple times (re-enable auth is a no-op if already enabled, policy and role are overwritten).

## Interfaces / Interfacce

| Interface / Interfaccia | Type / Tipo | Description / Descrizione |
|-------------------------|-------------|---------------------------|
| `provision-approle.sh` | Shell script | Input: VAULT_ADDR, VAULT_TOKEN (root token from unseal keys). Output: role_id, secret_id on stdout |
| AppRole auth method | Vault API | `POST /v1/sys/auth/approle` — enable auth backend |
| Policy `consumer-app-policy` | Vault policy (HCL) | `path "secret/data/acme/*" { capabilities = ["read", "list"] }` |
| AppRole `consumer-app` | Vault role | Bound to `consumer-app-policy`, `secret_id_ttl=24h`, `token_ttl=1h` |
| KV-v2 secret `secret/acme/db` | Vault secret | `{"password": "s3cret"}` — test secret for injection |
| `role_id` | String (stdout) | UUID identifying the AppRole — relatively static |
| `secret_id` | String (stdout) | UUID authenticating the AppRole — TTL 24h, must be rotated |

## Constraints / Vincoli

- Language / Linguaggio: Bash
- Framework: OpenBao/Vault CLI (`vault` command)
- Dependencies / Dipendenze: `vault` CLI available in the OpenBao pod or locally, access to VAULT_TOKEN (root token from unseal keys Secret)
- Patterns / Pattern: `set -euo pipefail`. Idempotent (safe to re-run). No interactive prompts.

### Security (from threat model)

- **`secret_id_ttl=24h`**: the secret_id expires after 24 hours. In production, use `secret_id_num_uses=1` with response wrapping for single-use delivery.
- **`token_ttl=1h`**: tokens issued by AppRole login expire after 1 hour. Limits blast radius of a leaked token.
- **Policy must scope to `secret/data/acme/*`** — NOT `secret/*` or `secret/data/*`. Overly broad policy allows tenant escape.
- **BATS verification**: test that the AppRole's token TTL is <= 1h after login. Test that the policy path matches `secret/data/acme/*`.
- **Root token handling**: the script needs the root token to configure AppRole. The root token is read from the unseal keys K8s Secret — never hardcoded in the script.

## Best Practices

- Error handling: `set -euo pipefail`. Check that OpenBao is sealed/unsealed before proceeding. Fail with clear error if VAULT_ADDR or VAULT_TOKEN is not set.
- Naming: AppRole name `consumer-app`, policy `consumer-app-policy` — descriptive and tenant-scoped.
- Style: HCL policy embedded as heredoc in the script. Comments explain each step.

## Test Requirements

| Type / Tipo | What / Cosa | Coverage |
|-------------|-------------|----------|
| Integration | AppRole auth method is enabled | `vault auth list` includes `approle/` |
| Integration | Policy is correctly scoped | `vault policy read consumer-app-policy` matches expected HCL |
| Integration | AppRole login succeeds | `vault write auth/approle/login role_id=... secret_id=...` returns a token |
| Integration | Issued token has TTL <= 1h | Token lookup shows `ttl` <= 3600 |
| Integration | Test secret is readable with the token | `vault kv get secret/acme/db` returns `password=s3cret` |
| Security | Token cannot read outside scoped path | `vault kv get secret/other/path` with AppRole token fails (403) |

## Acceptance Criteria / Criteri di Accettazione

- [ ] `scenarios/scen-secret-inject/scripts/provision-approle.sh` exists and passes `bash -n` syntax check
- [ ] Script uses `set -euo pipefail`
- [ ] AppRole auth method is enabled on the tenant's OpenBao
- [ ] Policy `consumer-app-policy` scopes to `secret/data/acme/*` only
- [ ] AppRole `consumer-app` has `secret_id_ttl=24h` and `token_ttl=1h`
- [ ] Script outputs `role_id` and `secret_id` for downstream consumption
- [ ] Test secret `secret/acme/db` with `password=s3cret` is written
- [ ] Script is idempotent (safe to run multiple times)
- [ ] No secrets are hardcoded in the script (VAULT_TOKEN from env or K8s Secret)

## Context / Contesto

- [ ] `.forgia/fd/FD-004-cross-cluster-secret-injection.md` — AppRole auth flow in sequence diagram
- [ ] `.forgia/fd/FD-004-threat-model.md` — AppRole credentials STRIDE analysis, TTL recommendations
- [ ] `tests/07-openbao.bats` — reference for `vault` CLI exec patterns (exec into pod, env vars)
- [ ] `manifests/plugins/kustomize/openbao-tenant-template/vault-cr-template.yaml` — Vault CR externalConfig structure

## Constitution Check

- [x] Respects code standards (shell `set -euo pipefail`, YAML 2-space indent)
- [x] Respects commit conventions (`feat(FD-004): ...`)
- [x] No hardcoded secrets (VAULT_TOKEN from env/K8s Secret, AppRole creds output to stdout only)
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
  - `scenarios/scen-secret-inject/scripts/provision-approle.sh`

### Retrospective / Retrospettiva

- **What worked / Cosa ha funzionato**:
- **What didn't / Cosa non ha funzionato**:
- **Suggestions for future FDs / Suggerimenti per FD futuri**:
