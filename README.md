# fury-baobank

Lab for testing **OpenBao** + **Bank-Vaults** together on Kubernetes Fury Distribution.

## What this lab does

Deploys a complete secret management stack on a local Kind cluster:

1. **OpenBao** — secret storage server (Vault-compatible, MPL 2.0)
2. **Bank-Vaults Operator** — deploys and manages OpenBao on K8s
3. **Bank-Vaults Webhook** — mutating webhook for transparent secret injection into pods
4. **Sample app** — demonstrates secret injection without any Vault-aware code

## Why

- Validate that Bank-Vaults tooling works with OpenBao (API-compatible but not officially supported)
- Provide a reference for a future KFD `secrets` module
- Test scenarios: unseal, HA, secret injection, rotation

## Quick start

```bash
mise install
mise run setup-all
mise run scenario-inject
```

Ask Claude Code:
> "Show me the injected secrets in the sample-app pod"

## Structure

```
fury-baobank/
  .zlab.yaml           Kind cluster config (3 nodes, zone labels for multi-zone tests)
  mise.toml            Task definitions (up, setup, scenarios, test)
  furyctl.yaml         Minimal KFD distribution (monitoring for observability)
  cluster/             Extra Kind config
  manifests/           OpenBao + Bank-Vaults manifests (Kustomize)
    openbao/           OpenBao StatefulSet, config, auto-unseal
    bank-vaults/       Operator + webhook deployment
    sample-app/        Test app demonstrating secret injection
  scripts/             Helper scripts (init, unseal, seed secrets)
  scenarios/           Test scenarios with expected flow
  tests/               BATS tests
```

## Scenarios

| # | Name | What it tests |
|---|---|---|
| 1 | [secret-injection](scenarios/01-secret-injection.md) | Pod gets secret via webhook, no code changes |
| 2 | [auto-unseal](scenarios/02-auto-unseal.md) | OpenBao auto-unseals after restart |
| 3 | [dynamic-db](scenarios/03-dynamic-db.md) | App gets dynamic DB credentials that rotate |
| 4 | [ha-failover](scenarios/04-ha-failover.md) | Kill leader, cluster continues |

## Notes

- Bank-Vaults officially supports Vault 1.11.x-1.14.x. OpenBao claims API compatibility.
  This lab validates that claim.
- For unseal in the lab we use a local Kubernetes Secret (NOT production-safe).
  Production would use AWS KMS, GCP KMS, Azure Key Vault, or HSM.

## References

- OpenBao: https://openbao.org/
- Bank-Vaults: https://bank-vaults.dev/docs/
- Docs comparison: [internal openbao-vs-bankvaults](https://github.com/Deepzima/fury-workspace/blob/main/tmp/openbao-vs-bankvaults.md) (private)
