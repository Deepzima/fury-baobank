---
id: "SDD-001"
fd: "FD-005"
title: "PKI engine setup via Vault CR externalConfig"
status: assigned
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-18"
started: ""
completed: ""
tags: [pki, ca, setup, root-ca, intermediate-ca]
---

# SDD-001: PKI engine setup via Vault CR externalConfig

> Parent FD: [[FD-005]]
> Depends on: none (first SDD in chain)
> Consumed by: [[SDD-002]], [[SDD-003]], [[SDD-004]], [[SDD-005]]

## Scope

Enable `pki-root` and `pki-k8s` PKI secret engine mounts on a test tenant's OpenBao instance. All operations via vault CLI (Vault CR externalConfig for PKI setup is limited -- use scripts).

What to build:

1. **Setup script** at `scenarios/scen-pki-ca/scripts/setup-pki.sh` (`set -euo pipefail`)
2. **Enable `pki-root/` engine** -- mount type `pki`, max_lease_ttl=87600h (10y)
3. **Generate internal Root CA** -- `vault write pki-root/root/generate/internal` with CN=baobank-root-ca, ttl=87600h, key_type=rsa, key_bits=4096
4. **Enable `pki-k8s/` engine** -- mount type `pki`, max_lease_ttl=8760h (1y)
5. **Generate Intermediate CSR** -- `vault write pki-k8s/intermediate/generate/internal` with CN=baobank-k8s-intermediate-ca
6. **Sign CSR with Root CA** -- `vault write pki-root/root/sign-intermediate` with the CSR, ttl=43800h (5y)
7. **Set signed intermediate cert** -- `vault write pki-k8s/intermediate/set-signed certificate=@signed.pem`
8. **Configure CRL + issuing URLs** -- `vault write pki-k8s/config/urls` with issuing_certificates and crl_distribution_points pointing to OpenBao's address
9. **Idempotency** -- script checks if engines are already mounted before re-creating

## Interfaces

| Interface | Type | Description |
|-----------|------|-------------|
| `scenarios/scen-pki-ca/scripts/setup-pki.sh` | shell script | Main setup script, requires VAULT_ADDR and VAULT_TOKEN env vars |
| `pki-root/` | Vault mount | Root CA engine (type: pki) |
| `pki-k8s/` | Vault mount | Intermediate CA engine (type: pki) |
| `pki-root/root/generate/internal` | Vault API | Generates internal Root CA (key never exported) |
| `pki-k8s/intermediate/generate/internal` | Vault API | Generates Intermediate CA CSR |
| `pki-root/root/sign-intermediate` | Vault API | Signs Intermediate CSR with Root CA |
| `pki-k8s/config/urls` | Vault config | CRL and issuing certificate URLs |

## Constraints

- Language: Bash with `set -euo pipefail`
- Dependencies: `vault` CLI, `jq`, `openssl` (for chain verification)
- Environment: VAULT_ADDR and VAULT_TOKEN must be set
- Root CA key_type=rsa, key_bits=4096, ttl=87600h (10y)
- Intermediate CA key_type=rsa, key_bits=2048, ttl=43800h (5y)

### Security (from threat model)

- Root CA MUST use `type: internal` -- private key never leaves OpenBao
- Do NOT create roles on `pki-root/` -- Root CA only signs the Intermediate CSR
- BATS must verify `vault list pki-root/roles` returns empty (no roles)
- CA chain must validate with `openssl verify`
- No CA keys or certificates stored in files on disk (only transient during signing)

## Best Practices

- Script is idempotent: safe to run multiple times
- Error handling: `set -euo pipefail`, meaningful error messages on failure
- Temporary files (CSR, signed cert) cleaned up after use (`trap cleanup EXIT`)
- Use `vault secrets list` to check if engines are already mounted before enabling
- Log each step to stderr for debugging

## Test Requirements

| Type | What | Coverage |
|------|------|----------|
| BATS | `pki-root/` engine is mounted and type is `pki` | 1 test |
| BATS | `pki-k8s/` engine is mounted and type is `pki` | 1 test |
| BATS | Root CA cert exists and is self-signed | 1 test |
| BATS | Intermediate CA cert exists and is signed by Root CA | 1 test |
| BATS | CA chain validates end-to-end with `openssl verify` | 1 test |
| BATS | `vault list pki-root/roles` returns empty (no roles on Root) | 1 test |
| BATS | CRL URL is configured on `pki-k8s/` | 1 test |

**Minimum: 7 BATS tests** (in `tests/09-pki.bats`)

## Acceptance Criteria

- [ ] `pki-root/` engine mounted with max_lease_ttl=87600h
- [ ] `pki-k8s/` engine mounted with max_lease_ttl=8760h
- [ ] Root CA generated internally (type: internal, key_bits=4096)
- [ ] Intermediate CSR generated, signed by Root, and set on `pki-k8s/`
- [ ] CRL + issuing URLs configured on `pki-k8s/`
- [ ] No roles exist on `pki-root/` (Root CA is sign-only)
- [ ] CA chain validates with `openssl verify`
- [ ] Setup script is idempotent
- [ ] All BATS tests pass

## Context

- [ ] `.forgia/fd/FD-005-pki-ca-engine-k8s-certs.md` -- Feature Design
- [ ] `.forgia/fd/FD-005-threat-model.md` -- STRIDE threat model
- [ ] `tests/07-openbao.bats` -- reference BATS structure
- [ ] `manifests/plugins/kustomize/openbao-tenant-template/vault-cr-template.yaml` -- Vault CR template
- [ ] K8s PKI requirements: https://kubernetes.io/docs/setup/best-practices/certificates/

## Constitution Check

- [x] Respects code standards (YAML 2-space, shell `set -euo pipefail`)
- [x] Respects commit conventions (`feat(FD-005): ...`)
- [x] No hardcoded secrets (CA keys never in files, only in OpenBao internal storage)
- [x] Tests defined and sufficient (7 BATS tests)

---

## Work Log

### Agent

- **Executor**: <!-- openhands | claude-code | manual -->
- **Started**: <!-- timestamp -->
- **Completed**: <!-- timestamp -->
- **Duration**: <!-- total time -->

### Decisions

1. <!-- decision 1: what and why -->

### Output

- **Commit(s)**: <!-- hash -->
- **PR**: <!-- link -->
- **Files created/modified**:
  - `path/to/file`

### Retrospective

- **What worked**:
- **What didn't**:
- **Suggestions for future FDs**:
