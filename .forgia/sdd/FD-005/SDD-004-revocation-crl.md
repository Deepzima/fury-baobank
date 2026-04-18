---
id: "SDD-004"
fd: "FD-005"
title: "Revocation + CRL validation"
status: assigned
agent: "claude-code"
assigned_to: "claude-code"
created: "2026-04-18"
started: ""
completed: ""
tags: [pki, revocation, crl, testing]
---

# SDD-004: Revocation + CRL validation

> Parent FD: [[FD-005]]
> Depends on: [[SDD-001]] (PKI engines + CRL URLs), [[SDD-002]] (roles for issuance), [[SDD-003]] (test structure)
> Consumed by: [[SDD-005]] (integration wiring)

## Scope

Additional BATS tests (in `tests/09-pki.bats` or a dedicated section within it) covering certificate revocation and CRL validation. The tests exercise the full revocation lifecycle: issue a cert, revoke it by serial number, fetch the CRL, and verify the revoked serial appears in the CRL.

What to build:

1. **Issue a test certificate** from `pki-k8s/issue/k8s-apiserver` (or any role)
2. **Extract serial number** from the issued certificate
3. **Revoke the certificate** via `vault write pki-k8s/revoke serial_number=<serial>`
4. **Fetch CRL** from `/v1/pki-k8s/crl` (DER-encoded)
5. **Convert DER to PEM** using `openssl crl -inform DER -outform PEM`
6. **Parse CRL** and verify the revoked serial is listed
7. **Verify CRL is parseable** and contains valid issuer information

## Interfaces

| Interface | Type | Description |
|-----------|------|-------------|
| `vault write pki-k8s/revoke serial_number=<serial>` | Vault API | Revokes a certificate by serial number |
| `/v1/pki-k8s/crl` | HTTP endpoint | Fetches CRL in DER format |
| `/v1/pki-k8s/crl/pem` | HTTP endpoint | Fetches CRL in PEM format (if available) |
| `openssl crl -inform DER` | CLI | Converts and parses CRL |
| `openssl crl -text -noout` | CLI | Displays CRL contents including revoked serials |

## Constraints

- Language: Bash (BATS test framework)
- Dependencies: `vault` CLI, `openssl`, `curl`, `jq`, BATS
- CRL is DER-encoded by default from Vault/OpenBao
- Serial numbers in CRL may be formatted differently (uppercase hex, colon-separated) -- normalize for comparison
- Tests must handle timing: CRL may take a moment to update after revocation

### Security (from threat model)

- After revoking a certificate, fetch CRL within 5 seconds and verify the serial is listed
- CRL must be DER-encoded and parseable by openssl
- CRL must contain a valid issuer matching the Intermediate CA
- Verify that a non-revoked certificate's serial does NOT appear in the CRL (negative test)

## Best Practices

- Follow existing BATS patterns from `tests/07-openbao.bats`
- Normalize serial number format before comparison (strip colons, lowercase/uppercase)
- Use a small sleep (1-2s) between revocation and CRL fetch if needed
- Clean up temporary files (certs, CRL) in teardown
- Each test is self-contained: issues its own cert, revokes it, checks CRL

## Test Requirements

| Type | What | Coverage |
|------|------|----------|
| BATS | Issue cert, extract serial number | 1 test |
| BATS | Revoke cert by serial, verify revocation response | 1 test |
| BATS | Fetch CRL from /v1/pki-k8s/crl, verify it is valid DER | 1 test |
| BATS | Convert CRL DER to PEM, parse successfully | 1 test |
| BATS | Revoked serial appears in CRL text output | 1 test |
| BATS | CRL issuer matches Intermediate CA CN | 1 test |
| BATS | Non-revoked cert serial does NOT appear in CRL | 1 test |

**Minimum: 7 BATS tests** (in `tests/09-pki.bats`, revocation section)

## Acceptance Criteria

- [ ] Certificate can be revoked by serial number via `vault write pki-k8s/revoke`
- [ ] CRL is fetchable from `/v1/pki-k8s/crl`
- [ ] CRL is valid DER and convertible to PEM
- [ ] Revoked serial appears in CRL within 5 seconds of revocation
- [ ] CRL issuer matches the Intermediate CA
- [ ] Non-revoked certificate serial is absent from CRL
- [ ] All BATS tests pass and are idempotent

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
- [x] Tests defined and sufficient (7 BATS tests covering revocation lifecycle)

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
