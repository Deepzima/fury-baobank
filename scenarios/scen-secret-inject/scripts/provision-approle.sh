#!/usr/bin/env bash
# Provision cross-cluster Kubernetes auth on the tenant's OpenBao (FD-004).
#
# Registers the consumer cluster's API server as a trusted identity source
# in OpenBao. The webhook on the consumer cluster sends pod SA tokens here,
# and OpenBao validates them via TokenReview against the consumer API server.
#
# This replaces AppRole — no static credentials to manage.
#
# Usage: bash scenarios/scen-secret-inject/scripts/provision-approle.sh

set -euo pipefail

BAOBANK_CONTEXT="kind-fury-baobank"
CONSUMER_CONTEXT="kind-fury-baobank-consumer"
TENANT_NS="scen-acme"
SCENARIO_DIR="scenarios/scen-secret-inject"
VAULT_ADDR_FILE="${SCENARIO_DIR}/.vault-addr"

if [ ! -f "${VAULT_ADDR_FILE}" ]; then
  echo "ERROR: ${VAULT_ADDR_FILE} not found. Run setup-consumer.sh first."
  exit 1
fi

# Get root token
ROOT_TOKEN=$(kubectl --context "${BAOBANK_CONTEXT}" get secret -n "${TENANT_NS}" \
  reevo-ob-id-acme-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d)

OB_POD=$(kubectl --context "${BAOBANK_CONTEXT}" get pods -n "${TENANT_NS}" \
  -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

vault_cmd() {
  kubectl --context "${BAOBANK_CONTEXT}" exec -n "${TENANT_NS}" "${OB_POD}" -c vault -- \
    env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${ROOT_TOKEN}" vault "$@"
}

echo "==> [1/5] Discovering consumer cluster API server details"
CONSUMER_API_URL=$(kubectl --context "${CONSUMER_CONTEXT}" config view --minify -o jsonpath='{.clusters[0].cluster.server}')
# On Kind, the internal API URL uses the container name. We need the Docker IP.
CONSUMER_CP_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fury-baobank-consumer-control-plane)
CONSUMER_API_URL="https://${CONSUMER_CP_IP}:6443"
echo "    Consumer API: ${CONSUMER_API_URL}"

# Extract the consumer cluster CA cert
kubectl --context "${CONSUMER_CONTEXT}" config view --raw --minify --flatten \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > /tmp/consumer-ca.pem
echo "    Consumer CA cert extracted"

echo "==> [2/5] Enabling Kubernetes auth mount for consumer cluster"
vault_cmd auth enable -path=kubernetes-consumer kubernetes 2>/dev/null || echo "    (already enabled)"

echo "==> [3/5] Configuring consumer cluster trust"
# Create a token reviewer SA on the consumer cluster for TokenReview validation
kubectl --context "${CONSUMER_CONTEXT}" apply -f - <<'REVIEWEREOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-token-reviewer
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-token-reviewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: vault-token-reviewer
    namespace: kube-system
REVIEWEREOF
REVIEWER_JWT=$(kubectl --context "${CONSUMER_CONTEXT}" create token vault-token-reviewer -n kube-system --duration=8760h)

# Copy the CA cert into the OpenBao pod and configure the auth mount
kubectl --context "${BAOBANK_CONTEXT}" cp /tmp/consumer-ca.pem \
  "${TENANT_NS}/${OB_POD}:/tmp/consumer-ca.pem" -c vault

vault_cmd write auth/kubernetes-consumer/config \
  kubernetes_host="${CONSUMER_API_URL}" \
  kubernetes_ca_cert=@/tmp/consumer-ca.pem \
  token_reviewer_jwt="${REVIEWER_JWT}"

echo "==> [4/5] Creating auth role + policy for consumer apps"
POLICY='path "secret/data/acme/*" { capabilities = ["read", "list"] } path "secret/metadata/acme/*" { capabilities = ["read", "list"] }'
kubectl --context "${BAOBANK_CONTEXT}" exec -n "${TENANT_NS}" "${OB_POD}" -c vault -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${ROOT_TOKEN}" \
  sh -c "echo '${POLICY}' | vault policy write consumer-app -"

vault_cmd write auth/kubernetes-consumer/role/consumer-app \
  bound_service_account_names="consumer-sa" \
  bound_service_account_namespaces="consumer-app" \
  policies="consumer-app" \
  ttl=1h

echo "==> [5/5] Writing test secret"
vault_cmd kv put secret/acme/db password=cross-cluster-s3cret username=acme-app

echo ""
echo "==> Cross-cluster Kubernetes auth configured"
echo "    Auth mount: auth/kubernetes-consumer"
echo "    Role: consumer-app (SA=consumer-sa, NS=consumer-app)"
echo "    Policy: secret/data/acme/* (read-only)"
echo ""
echo "    Next: bash ${SCENARIO_DIR}/scripts/deploy-consumer-app.sh"
