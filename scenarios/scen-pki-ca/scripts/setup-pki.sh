#!/usr/bin/env bash
# Setup PKI engine on the tenant's OpenBao: Root CA + Intermediate CA (FD-005 SDD-001).
#
# Creates a two-tier PKI:
#   pki-root  → Root CA (internal, 10y TTL, offline after signing Intermediate)
#   pki-k8s   → Intermediate CA (online, 1y TTL, issues leaf certs)
#
# Usage: bash scenarios/scen-pki-ca/scripts/setup-pki.sh

set -euo pipefail

BAOBANK_CONTEXT="kind-fury-baobank"
TENANT_NS="scen-acme"
VAULT_NAME="reevo-ob-id-acme"
SCENARIO_DIR="scenarios/scen-pki-ca"

# Get root token + pod
ROOT_TOKEN=$(kubectl --context "${BAOBANK_CONTEXT}" get secret -n "${TENANT_NS}" \
  "${VAULT_NAME}-unseal-keys" -o jsonpath='{.data.vault-root}' | base64 -d)
OB_POD=$(kubectl --context "${BAOBANK_CONTEXT}" get pods -n "${TENANT_NS}" \
  -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

vault_cmd() {
  kubectl --context "${BAOBANK_CONTEXT}" exec -n "${TENANT_NS}" "${OB_POD}" -c vault -- \
    env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${ROOT_TOKEN}" vault "$@"
}

echo "==> [1/7] Enabling PKI Root CA engine"
vault_cmd secrets enable -path=pki-root pki 2>/dev/null || echo "    (already enabled)"
vault_cmd secrets tune -max-lease-ttl=87600h pki-root

echo "==> [2/7] Generating internal Root CA"
vault_cmd write -format=json pki-root/root/generate/internal \
  common_name="Reevo Root CA" \
  ttl=87600h \
  key_bits=4096 \
  > /dev/null
echo "    Root CA generated (internal, 10y TTL, 4096-bit RSA)"

echo "==> [3/7] Configuring Root CA URLs"
vault_cmd write pki-root/config/urls \
  issuing_certificates="http://${VAULT_NAME}.${TENANT_NS}:8200/v1/pki-root/ca" \
  crl_distribution_points="http://${VAULT_NAME}.${TENANT_NS}:8200/v1/pki-root/crl"

echo "==> [4/7] Enabling PKI Intermediate CA engine"
vault_cmd secrets enable -path=pki-k8s pki 2>/dev/null || echo "    (already enabled)"
vault_cmd secrets tune -max-lease-ttl=43800h pki-k8s

echo "==> [5/7] Generating Intermediate CSR + signing with Root"
# Generate CSR
vault_cmd write -format=json pki-k8s/intermediate/generate/internal \
  common_name="Reevo K8s Intermediate CA" \
  key_bits=4096 \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['csr'])" \
  > /tmp/pki-k8s-csr.pem

# Copy CSR into pod for signing
kubectl --context "${BAOBANK_CONTEXT}" cp /tmp/pki-k8s-csr.pem \
  "${TENANT_NS}/${OB_POD}:/tmp/pki-k8s-csr.pem" -c vault

# Sign with Root CA
vault_cmd write -format=json pki-root/root/sign-intermediate \
  csr=@/tmp/pki-k8s-csr.pem \
  format=pem_bundle \
  ttl=43800h \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['certificate'])" \
  > /tmp/pki-k8s-signed.pem

echo "    Intermediate CA signed by Root (5y TTL)"

echo "==> [6/7] Setting signed Intermediate certificate"
kubectl --context "${BAOBANK_CONTEXT}" cp /tmp/pki-k8s-signed.pem \
  "${TENANT_NS}/${OB_POD}:/tmp/pki-k8s-signed.pem" -c vault

vault_cmd write pki-k8s/intermediate/set-signed \
  certificate=@/tmp/pki-k8s-signed.pem

echo "==> [7/7] Configuring Intermediate CA URLs"
vault_cmd write pki-k8s/config/urls \
  issuing_certificates="http://${VAULT_NAME}.${TENANT_NS}:8200/v1/pki-k8s/ca" \
  crl_distribution_points="http://${VAULT_NAME}.${TENANT_NS}:8200/v1/pki-k8s/crl"

echo ""
echo "==> PKI two-tier CA setup complete"
echo "    Root CA:         pki-root/ (Reevo Root CA, 10y, internal)"
echo "    Intermediate CA: pki-k8s/  (Reevo K8s Intermediate CA, 5y)"
echo ""
echo "    Next: bash ${SCENARIO_DIR}/scripts/setup-roles.sh"
