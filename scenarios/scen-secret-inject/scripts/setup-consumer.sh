#!/usr/bin/env bash
# Setup script for cross-cluster secret injection scenario (FD-004).
#
# Creates: scenario tenant + OpenBao on baobank, consumer Kind cluster,
#          NodePort exposure, VAULT_ADDR discovery.
#
# Manifests: scenarios/scen-secret-inject/manifests/
# Usage:     bash scenarios/scen-secret-inject/scripts/setup-consumer.sh

set -euo pipefail

BAOBANK_CONTEXT="kind-fury-baobank"
CONSUMER_CLUSTER="fury-baobank-consumer"
CONSUMER_CONTEXT="kind-${CONSUMER_CLUSTER}"
TENANT_NS="scen-acme"
VAULT_NAME="reevo-ob-id-acme"
SCENARIO_DIR="scenarios/scen-secret-inject"
BAO_MANIFESTS="${SCENARIO_DIR}/manifests/tenant-bao"
VAULT_ADDR_FILE="${SCENARIO_DIR}/.vault-addr"

echo "==> [1/6] Provisioning scenario tenant + OpenBao on baobank"
kubectl --context "${BAOBANK_CONTEXT}" apply -f "${BAO_MANIFESTS}/tenant-acme.yaml"

kubectl --context "${BAOBANK_CONTEXT}" create namespace "${TENANT_NS}" \
  --dry-run=client -o yaml | kubectl --context "${BAOBANK_CONTEXT}" apply -f - 2>/dev/null

echo "    Waiting for namespace ${TENANT_NS}..."
until kubectl --context "${BAOBANK_CONTEXT}" get sa default -n "${TENANT_NS}" &>/dev/null; do sleep 1; done

kubectl --context "${BAOBANK_CONTEXT}" apply -f "${BAO_MANIFESTS}/vault-rbac-acme.yaml"
kubectl --context "${BAOBANK_CONTEXT}" apply -f "${BAO_MANIFESTS}/vault-cr-acme.yaml"

echo "    Waiting for OpenBao to init + unseal (up to 3 min)..."
until kubectl --context "${BAOBANK_CONTEXT}" get pods -n "${TENANT_NS}" \
  -l app.kubernetes.io/name=vault \
  -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True; do
  sleep 5
done
echo "    OpenBao Ready!"

echo "    Waiting for configurer to reconcile policies..."
OB_POD=$(kubectl --context "${BAOBANK_CONTEXT}" get pods -n "${TENANT_NS}" \
  -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')
ROOT_TOKEN=$(kubectl --context "${BAOBANK_CONTEXT}" get secret -n "${TENANT_NS}" \
  "${VAULT_NAME}-unseal-keys" -o jsonpath='{.data.vault-root}' | base64 -d)
until kubectl --context "${BAOBANK_CONTEXT}" exec -n "${TENANT_NS}" "${OB_POD}" -c vault -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${ROOT_TOKEN}" \
  vault policy list 2>/dev/null | grep -q acme-admin; do
  sleep 5
done
echo "    Configurer done!"

echo "==> [2/6] Exposing tenant OpenBao via NodePort"
kubectl --context "${BAOBANK_CONTEXT}" apply -f "${BAO_MANIFESTS}/nodeport-acme.yaml"
echo "    NodePort 30820 → OpenBao :8200"

echo "==> [3/6] Creating consumer Kind cluster"
if kind get clusters 2>/dev/null | grep -q "^${CONSUMER_CLUSTER}$"; then
  echo "    Consumer cluster already exists, skipping create"
else
  kind create cluster --config "${SCENARIO_DIR}/cluster/kind-consumer.yaml" --wait 60s
fi

echo "==> [4/6] Discovering baobank Docker IP"
BAOBANK_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fury-baobank-control-plane)
if [ -z "${BAOBANK_IP}" ]; then
  echo "ERROR: could not discover baobank control-plane Docker IP"
  exit 1
fi
echo "    Baobank Docker IP: ${BAOBANK_IP}"

VAULT_ADDR="http://${BAOBANK_IP}:30820"
echo "${VAULT_ADDR}" > "${VAULT_ADDR_FILE}"
echo "    VAULT_ADDR: ${VAULT_ADDR}"

echo "==> [5/6] Verifying OpenBao reachable from consumer cluster"
kubectl --context "${CONSUMER_CONTEXT}" run vault-test \
  --image=curlimages/curl:8.9.1 \
  --restart=Never \
  --rm -i --wait \
  --command -- curl -sf --max-time 5 "${VAULT_ADDR}/v1/sys/health" && \
  echo "    Connectivity OK!" || \
  echo "    WARNING: OpenBao not yet reachable. May need a few seconds."

echo ""
echo "==> [6/6] Setup complete"
echo "    VAULT_ADDR: ${VAULT_ADDR}"
echo "    Next: bash ${SCENARIO_DIR}/scripts/provision-approle.sh"
