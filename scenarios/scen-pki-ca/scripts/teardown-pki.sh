#!/usr/bin/env bash
# Teardown PKI engines (FD-005).
set -euo pipefail

BAOBANK_CONTEXT="kind-fury-baobank"
TENANT_NS="scen-acme"
VAULT_NAME="reevo-ob-id-acme"

ROOT_TOKEN=$(kubectl --context "${BAOBANK_CONTEXT}" get secret -n "${TENANT_NS}" \
  "${VAULT_NAME}-unseal-keys" -o jsonpath='{.data.vault-root}' | base64 -d)
OB_POD=$(kubectl --context "${BAOBANK_CONTEXT}" get pods -n "${TENANT_NS}" \
  -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

vault_cmd() {
  kubectl --context "${BAOBANK_CONTEXT}" exec -n "${TENANT_NS}" "${OB_POD}" -c vault -- \
    env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${ROOT_TOKEN}" vault "$@"
}

echo "==> Disabling PKI engines"
vault_cmd secrets disable pki-k8s 2>/dev/null || true
vault_cmd secrets disable pki-root 2>/dev/null || true
rm -f /tmp/pki-k8s-csr.pem /tmp/pki-k8s-signed.pem

echo "==> PKI teardown complete"
