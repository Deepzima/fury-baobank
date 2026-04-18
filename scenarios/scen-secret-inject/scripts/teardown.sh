#!/usr/bin/env bash
# Teardown the cross-cluster scenario (FD-004).
set -euo pipefail

BAOBANK_CONTEXT="kind-fury-baobank"
CONSUMER_CLUSTER="fury-baobank-consumer"
SCENARIO_DIR="scenarios/scen-secret-inject"

echo "==> Deleting consumer cluster"
kind delete cluster --name "${CONSUMER_CLUSTER}" 2>/dev/null || true

echo "==> Cleaning up scenario tenant on baobank"
kubectl --context "${BAOBANK_CONTEXT}" delete vault reevo-ob-id-acme -n scen-acme --ignore-not-found --wait=false >/dev/null 2>&1 || true
kubectl --context "${BAOBANK_CONTEXT}" delete svc reevo-ob-id-acme-nodeport -n scen-acme --ignore-not-found >/dev/null 2>&1 || true
kubectl --context "${BAOBANK_CONTEXT}" delete tenant scen-acme --ignore-not-found --wait=false >/dev/null 2>&1 || true
kubectl --context "${BAOBANK_CONTEXT}" delete ns scen-acme --ignore-not-found --wait=false >/dev/null 2>&1 || true

echo "==> Removing runtime files"
rm -f "${SCENARIO_DIR}/.vault-addr" "${SCENARIO_DIR}/.approle-creds"

echo "==> Teardown complete"
