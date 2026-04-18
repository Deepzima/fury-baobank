#!/usr/bin/env bash
# Create PKI roles for Kubernetes components (FD-005 SDD-002).
#
# Roles on pki-k8s/ (Intermediate CA):
#   k8s-apiserver    → server cert with K8s API SANs
#   k8s-kubelet      → client cert with system:node CN + system:nodes O
#   k8s-etcd         → server+client cert with etcd SANs
#   k8s-front-proxy  → client-only cert for front-proxy
#
# All roles: max_ttl=24h, key_bits=2048, enforce_hostnames=true
#
# Usage: bash scenarios/scen-pki-ca/scripts/setup-roles.sh

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

echo "==> [1/4] Creating role: k8s-apiserver"
vault_cmd write pki-k8s/roles/k8s-apiserver \
  allowed_domains="kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster.local" \
  allow_bare_domains=true \
  allow_subdomains=false \
  allow_ip_sans=true \
  enforce_hostnames=true \
  server_flag=true \
  client_flag=false \
  key_type=rsa \
  key_bits=2048 \
  max_ttl=24h \
  ttl=24h
echo "    SANs: kubernetes, kubernetes.default, kubernetes.default.svc, kubernetes.default.svc.cluster.local, + IP SANs"

echo "==> [2/4] Creating role: k8s-kubelet"
# CN contains colons (system:node:<hostname>) which is not a valid hostname.
# Use allow_any_name=true + enforce_hostnames=false to permit this.
# The organization field forces O=system:nodes in all issued certs.
vault_cmd write pki-k8s/roles/k8s-kubelet \
  allow_any_name=true \
  enforce_hostnames=false \
  server_flag=false \
  client_flag=true \
  key_type=rsa \
  key_bits=2048 \
  max_ttl=24h \
  ttl=24h \
  organization="system:nodes"
echo "    CN: system:node:<hostname>, O: system:nodes, EKU: Client Auth"

echo "==> [3/4] Creating role: k8s-etcd"
vault_cmd write pki-k8s/roles/k8s-etcd \
  allowed_domains="etcd,localhost" \
  allow_bare_domains=true \
  allow_subdomains=true \
  allow_ip_sans=true \
  enforce_hostnames=true \
  server_flag=true \
  client_flag=true \
  key_type=rsa \
  key_bits=2048 \
  max_ttl=24h \
  ttl=24h
echo "    SANs: etcd hostnames + IPs, EKU: Server Auth + Client Auth"

echo "==> [4/4] Creating role: k8s-front-proxy"
vault_cmd write pki-k8s/roles/k8s-front-proxy \
  allowed_domains="front-proxy-client" \
  allow_bare_domains=true \
  allow_subdomains=false \
  enforce_hostnames=false \
  server_flag=false \
  client_flag=true \
  key_type=rsa \
  key_bits=2048 \
  max_ttl=24h \
  ttl=24h
echo "    CN: front-proxy-client, EKU: Client Auth only"

echo ""
echo "==> All 4 PKI roles created on pki-k8s/"
echo "    Next: bash scenarios/scen-pki-ca/scripts/test or mise run scen:pki-ca:test"
