#!/usr/bin/env bats

# Cross-cluster secret injection tests (FD-004).
# Validates: webhook on consumer cluster injects secrets from remote OpenBao
# using cross-cluster Kubernetes auth (no AppRole, no static credentials).

BAOBANK_CONTEXT="kind-fury-baobank"
CONSUMER_CONTEXT="kind-fury-baobank-consumer"
TENANT_NS="scen-acme"
SCENARIO_DIR="scenarios/scen-secret-inject"

bkctl() {
  kubectl --context "${BAOBANK_CONTEXT}" "$@"
}

ckctl() {
  kubectl --context "${CONSUMER_CONTEXT}" "$@"
}

setup_file() {
  if ! kind get clusters 2>/dev/null | grep -q "fury-baobank$"; then
    echo "FATAL: fury-baobank cluster not found" >&2
    return 1
  fi
  if ! kind get clusters 2>/dev/null | grep -q "fury-baobank-consumer"; then
    echo "FATAL: fury-baobank-consumer not found — run 'mise run scen:secret-inject:up'" >&2
    return 1
  fi
}

# --- Consumer cluster health ---

@test "Consumer cluster fury-baobank-consumer exists" {
  run kind get clusters
  [[ "$output" == *"fury-baobank-consumer"* ]]
}

@test "Consumer cluster has 1 node Ready" {
  run ckctl get nodes --no-headers
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
  [[ "$output" == *"Ready"* ]]
}

# --- OpenBao reachable from consumer ---

@test "OpenBao NodePort Service exists on baobank" {
  run bkctl get svc reevo-ob-id-acme-nodeport -n "${TENANT_NS}" -o jsonpath='{.spec.type}'
  [ "$status" -eq 0 ]
  [ "$output" = "NodePort" ]
}

@test "VAULT_ADDR file exists and is valid" {
  [ -f "${SCENARIO_DIR}/.vault-addr" ]
  VAULT_ADDR=$(cat "${SCENARIO_DIR}/.vault-addr")
  [[ "$VAULT_ADDR" == http://* ]]
}

# --- Cross-cluster Kubernetes auth ---

@test "Kubernetes auth mount for consumer exists on OpenBao" {
  local ob_pod token
  ob_pod=$(bkctl get pods -n "${TENANT_NS}" -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')
  token=$(bkctl get secret -n "${TENANT_NS}" reevo-ob-id-acme-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d)
  run bkctl exec -n "${TENANT_NS}" "${ob_pod}" -c vault -- \
    env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${token}" \
    vault auth list -format=json
  [ "$status" -eq 0 ]
  [[ "$output" == *"kubernetes-consumer"* ]]
}

@test "Consumer auth role is scoped to consumer-sa in consumer-app namespace" {
  local ob_pod token
  ob_pod=$(bkctl get pods -n "${TENANT_NS}" -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')
  token=$(bkctl get secret -n "${TENANT_NS}" reevo-ob-id-acme-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d)
  run bkctl exec -n "${TENANT_NS}" "${ob_pod}" -c vault -- \
    env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${token}" \
    vault read -format=json auth/kubernetes-consumer/role/consumer-app
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ns = d['data']['bound_service_account_namespaces']
sa = d['data']['bound_service_account_names']
assert 'consumer-app' in ns, f'expected consumer-app in {ns}'
assert 'consumer-sa' in sa, f'expected consumer-sa in {sa}'
"
}

@test "Consumer policy is scoped to secret/data/acme/* (not secret/*)" {
  local ob_pod token
  ob_pod=$(bkctl get pods -n "${TENANT_NS}" -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')
  token=$(bkctl get secret -n "${TENANT_NS}" reevo-ob-id-acme-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d)
  run bkctl exec -n "${TENANT_NS}" "${ob_pod}" -c vault -- \
    env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${token}" \
    vault policy read consumer-app
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret/data/acme/*"* ]]
}

# --- Webhook on consumer cluster ---

@test "Bank-Vaults webhook is running on consumer cluster" {
  run ckctl get deployment -n bank-vaults-system vault-secrets-webhook -o jsonpath='{.status.readyReplicas}'
  [ "$status" -eq 0 ]
  [ "${output:-0}" -ge 1 ]
}

# --- Secret injection ---

@test "Consumer app deployment is Ready" {
  run ckctl get deployment consumer-app -n consumer-app -o jsonpath='{.status.readyReplicas}'
  [ "$status" -eq 0 ]
  [ "${output:-0}" -ge 1 ]
}

@test "Consumer app has injected DB_PASSWORD from remote OpenBao" {
  local pod_name
  pod_name=$(ckctl get pods -n consumer-app -l app=consumer-app -o jsonpath='{.items[0].metadata.name}')
  run ckctl logs -n consumer-app "${pod_name}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DB_PASSWORD=cross-cluster-s3cret"* ]]
}

@test "Consumer app has injected DB_USERNAME from remote OpenBao" {
  local pod_name
  pod_name=$(ckctl get pods -n consumer-app -l app=consumer-app -o jsonpath='{.items[0].metadata.name}')
  run ckctl logs -n consumer-app "${pod_name}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DB_USERNAME=acme-app"* ]]
}

# --- Security checks ---

@test "No static AppRole credentials on consumer cluster" {
  # With K8s auth cross-cluster, there should be NO vault-approle Secret
  run ckctl get secret vault-approle -n consumer-app -o name 2>&1
  [ "$status" -ne 0 ]
}

@test "Consumer app uses ServiceAccount consumer-sa (not default)" {
  local sa
  sa=$(ckctl get deployment consumer-app -n consumer-app \
    -o jsonpath='{.spec.template.spec.serviceAccountName}')
  [ "$sa" = "consumer-sa" ]
}
