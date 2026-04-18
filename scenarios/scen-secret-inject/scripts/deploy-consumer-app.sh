#!/usr/bin/env bash
# Deploy Bank-Vaults webhook + consumer app on the consumer cluster (FD-004).
#
# Installs ONLY the webhook (no operator, no Vault) on the consumer cluster.
# The webhook reads pod annotations and injects secrets from the remote OpenBao
# using cross-cluster Kubernetes auth.
#
# Usage: bash scenarios/scen-secret-inject/scripts/deploy-consumer-app.sh

set -euo pipefail

CONSUMER_CONTEXT="kind-fury-baobank-consumer"
SCENARIO_DIR="scenarios/scen-secret-inject"
ENV_MANIFESTS="${SCENARIO_DIR}/manifests/tenant-env"
VAULT_ADDR_FILE="${SCENARIO_DIR}/.vault-addr"

if [ ! -f "${VAULT_ADDR_FILE}" ]; then
  echo "ERROR: Run setup-consumer.sh and provision script first."
  exit 1
fi

export VAULT_ADDR=$(cat "${VAULT_ADDR_FILE}")

echo "==> [1/3] Installing Bank-Vaults webhook on consumer cluster"
# Install webhook via Helm directly (no kustomize — consumer is minimal)
helm upgrade --install vault-secrets-webhook \
  oci://ghcr.io/bank-vaults/helm-charts/vault-secrets-webhook \
  --version 1.22.2 \
  --namespace bank-vaults-system \
  --create-namespace \
  --values "${ENV_MANIFESTS}/webhook-chart-values.yaml" \
  --kube-context "${CONSUMER_CONTEXT}" \
  --wait --timeout 120s

echo "==> [2/3] Deploying consumer app with vault annotations"
envsubst '${VAULT_ADDR}' < "${ENV_MANIFESTS}/consumer-app.yaml" | \
  kubectl --context "${CONSUMER_CONTEXT}" apply -f - >/dev/null

echo "==> [3/3] Waiting for consumer app to be Ready"
# Delete old pods to pick up new annotations if redeploying
kubectl --context "${CONSUMER_CONTEXT}" rollout restart deployment/consumer-app \
  -n consumer-app 2>/dev/null || true
kubectl --context "${CONSUMER_CONTEXT}" rollout status deployment/consumer-app \
  -n consumer-app --timeout=120s

echo ""
echo "==> Consumer app deployed with webhook injection"
echo "    kubectl --context ${CONSUMER_CONTEXT} logs -n consumer-app -l app=consumer-app"
