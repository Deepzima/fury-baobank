---
id: "SDD-003"
fd: "FD-005"
title: "Certificate issuance + validation BATS"
status: planned
agent: ""
assigned_to: ""
created: "2026-04-18"
started: ""
completed: ""
tags: [pki, bats, testing, certificates]
---

# SDD-003: Certificate issuance + validation BATS

> Parent FD: [[FD-005]]
> Depends on: [[SDD-001]] (PKI engines), [[SDD-002]] (PKI roles)
> Consumed by: [[SDD-005]] (integration wiring)

## Scope

Create BATS test suite `tests/09-pki.bats` covering certificate issuance from all 4 roles and full validation of the issued certificates. Tests verify SANs, CN, Organization, Key Usage, Extended Key Usage, TTL, key size, and end-to-end chain validation.

What to build:

1. **Test file** `tests/09-pki.bats` following the structure of `tests/07-openbao.bats`
2. **Setup helper** -- shared setup function that ensures VAULT_ADDR/VAULT_TOKEN are set
3. **PKI engine mount tests** (from SDD-001 scope)
4. **CA chain validation tests** (from SDD-001 scope)
5. **Role existence tests** (from SDD-002 scope)
6. **Certificate issuance tests**:
   - Issue cert from k8s-apiserver role, verify SANs match exactly (no extra SANs)
   - Issue cert from k8s-kubelet role, verify CN contains `system:node:`, O=`system:nodes`
   - Issue cert from k8s-etcd role, verify EKU contains both ServerAuth and ClientAuth
   - Issue cert from k8s-front-proxy role, verify EKU is ClientAuth only (no ServerAuth)
7. **Constraint validation tests**:
   - All issued certs have TTL <= 24h
   - All issued certs have key size >= 2048 bits
   - Full chain validates: leaf -> intermediate -> root with `openssl verify`

## Interfaces

| Interface | Type | Description |
|-----------|------|-------------|
| `tests/09-pki.bats` | BATS test file | Main PKI test suite |
| `vault write pki-k8s/issue/<role>` | Vault API | Issues certificates from a role |
| `openssl x509 -text` | CLI | Parses and inspects certificate fields |
| `openssl verify -CAfile` | CLI | Validates certificate chain |

## Constraints

- Language: Bash (BATS test framework)
- Dependencies: `vault` CLI, `openssl`, `jq`, BATS
- Tests must be non-destructive and repeatable
- Each test issues a fresh certificate (no reliance on cached certs)
- Temporary cert files cleaned up in teardown

### Security (from threat model)

- Verify SANs match EXACTLY -- no extra SANs beyond what the role allows
- Verify Key Usage and Extended Key Usage per cert type (ServerAuth vs ClientAuth)
- Verify TTL on every issued cert is <= 24h
- Verify key size on every issued cert is >= 2048 bits
- Chain validation with `openssl verify` -- leaf must chain to intermediate, intermediate to root
- Negative test: attempt to issue cert with unauthorized SAN, verify rejection

## Best Practices

- Follow existing BATS patterns from `tests/07-openbao.bats`
- Use `@test` annotations with descriptive names
- Use `setup_file` for one-time setup (port-forward, token retrieval)
- Use `teardown_file` for cleanup
- Each test is independent -- no ordering dependencies between individual tests
- Use `run` for commands that may fail, check `$status` and `$output`
- Parse certificates with `openssl x509 -noout -text` and grep/awk for fields

## Test Requirements

| Type | What | Coverage |
|------|------|----------|
| BATS | pki-root/ engine is mounted | 1 test |
| BATS | pki-k8s/ engine is mounted | 1 test |
| BATS | Root CA is self-signed | 1 test |
| BATS | Intermediate CA signed by Root | 1 test |
| BATS | CA chain validates with openssl verify | 1 test |
| BATS | No roles on pki-root/ | 1 test |
| BATS | CRL URL configured on pki-k8s/ | 1 test |
| BATS | k8s-apiserver role exists with correct config | 1 test |
| BATS | k8s-kubelet role exists with correct config | 1 test |
| BATS | k8s-etcd role exists with correct config | 1 test |
| BATS | k8s-front-proxy role exists with correct config | 1 test |
| BATS | Issue apiserver cert -- SANs correct | 1 test |
| BATS | Issue kubelet cert -- CN/O correct | 1 test |
| BATS | Issue etcd cert -- EKU ServerAuth+ClientAuth | 1 test |
| BATS | Issue front-proxy cert -- EKU ClientAuth only | 1 test |
| BATS | All certs TTL <= 24h | 1 test |
| BATS | All certs key size >= 2048 | 1 test |
| BATS | Leaf cert chain validates end-to-end | 1 test |
| BATS | Unauthorized SAN rejected | 1 test |

**Minimum: 19 BATS tests** (this file consolidates tests from SDD-001 and SDD-002 scope)

## Acceptance Criteria

- [ ] `tests/09-pki.bats` exists and follows project BATS conventions
- [ ] All PKI engine mount tests pass
- [ ] CA chain validation tests pass
- [ ] Certificate issuance from all 4 roles succeeds
- [ ] SAN verification: apiserver SANs match exactly (kubernetes, kubernetes.default, etc.)
- [ ] CN/O verification: kubelet cert has system:node:* CN, system:nodes O
- [ ] EKU verification: etcd has ServerAuth+ClientAuth, front-proxy has ClientAuth only
- [ ] TTL verification: all certs <= 24h
- [ ] Key size verification: all certs >= 2048 bits
- [ ] Chain validation: openssl verify succeeds for all issued certs
- [ ] Negative test: unauthorized SAN issuance is rejected
- [ ] Tests are idempotent and can run multiple times

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
- [x] Tests defined and sufficient (19 BATS tests covering all issuance and validation)

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
