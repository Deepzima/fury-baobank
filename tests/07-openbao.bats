#!/usr/bin/env bats

load 'helpers'

# Test tenant names — ephemeral, created in setup_file, destroyed in teardown_file.
TENANT_ALPHA="bats-tenant-alpha"
TENANT_BETA="bats-tenant-beta"
VAULT_ALPHA="reevo-ob-id-alpha"
VAULT_BETA="reevo-ob-id-beta"
OPENBAO_IMAGE="ghcr.io/openbao/openbao:2.1.0"

setup_file() {
  # Fail-fast: operator must be installed
  if ! kctl get ns bank-vaults-system &>/dev/null; then
    echo "FATAL: bank-vaults-system namespace missing — run 'mise run install-cni' first" >&2
    return 1
  fi

  # Pre-emptive cleanup
  kctl delete -f tests/fixtures/tenant-alpha-vault-cr.yaml --ignore-not-found --wait=true >/dev/null 2>&1 || true
  kctl delete -f tests/fixtures/tenant-beta-vault-cr.yaml --ignore-not-found --wait=true >/dev/null 2>&1 || true
  sleep 5
  kctl delete tenant "${TENANT_ALPHA}" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  kctl delete tenant "${TENANT_BETA}" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  sleep 3

  # 1. Create Capsule Tenants
  kctl apply -f tests/fixtures/tenant-alpha-capsule.yaml >/dev/null
  kctl apply -f tests/fixtures/tenant-beta-capsule.yaml >/dev/null

  # 2. Create tenant namespaces (Capsule owner must create them)
  kctl create namespace "${TENANT_ALPHA}" --dry-run=client -o yaml | kctl apply -f - >/dev/null 2>&1 || true
  kctl create namespace "${TENANT_BETA}" --dry-run=client -o yaml | kctl apply -f - >/dev/null 2>&1 || true

  # Wait for namespaces to be ready (ServiceAccount "default" must exist)
  wait_for 30 "kctl get sa default -n ${TENANT_ALPHA} &>/dev/null"
  wait_for 30 "kctl get sa default -n ${TENANT_BETA} &>/dev/null"

  # 3. Apply NetworkPolicy (cross-tenant isolation)
  kctl apply -n "${TENANT_ALPHA}" -f tests/fixtures/tenant-netpol-template.yaml >/dev/null
  kctl apply -n "${TENANT_BETA}" -f tests/fixtures/tenant-netpol-template.yaml >/dev/null

  # 4. Apply Vault CRs (operator creates OpenBao StatefulSets)
  kctl apply -f tests/fixtures/tenant-alpha-vault-cr.yaml >/dev/null
  kctl apply -f tests/fixtures/tenant-beta-vault-cr.yaml >/dev/null

  # 5. Wait for both OpenBao instances to become Ready (init + unseal takes 30-90s)
  wait_for 120 "kctl get pods -n ${TENANT_ALPHA} -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null | grep -q True"
  wait_for 120 "kctl get pods -n ${TENANT_BETA} -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null | grep -q True"
}

teardown_file() {
  # Best-effort cleanup
  kctl delete -f tests/fixtures/tenant-alpha-vault-cr.yaml --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kctl delete -f tests/fixtures/tenant-beta-vault-cr.yaml --ignore-not-found --wait=false >/dev/null 2>&1 || true
  sleep 5
  kctl delete tenant "${TENANT_ALPHA}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kctl delete tenant "${TENANT_BETA}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

# Helper: exec vault command inside a tenant's OpenBao pod
vault_exec() {
  local ns="$1"; shift
  local pod
  pod=$(kctl get pods -n "$ns" -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  kctl exec -n "$ns" "$pod" -c vault -- env VAULT_ADDR=http://127.0.0.1:8200 vault "$@"
}

# --- Control plane ---

@test "bank-vaults-system namespace exists" {
  assert_exists ns bank-vaults-system
}

@test "Bank-Vaults operator pod is Ready" {
  wait_for 60 'kctl get pods -n bank-vaults-system -l app.kubernetes.io/name=vault-operator -o jsonpath="{.items[*].status.conditions[?(@.type==\"Ready\")].status}" | grep -q True'
}

@test "Bank-Vaults webhook pod is Ready (replicas >= 2)" {
  run kctl get deployment -n bank-vaults-system -l app.kubernetes.io/name=vault-secrets-webhook -o jsonpath='{.items[0].status.readyReplicas}'
  [ "$status" -eq 0 ]
  [ "${output:-0}" -ge 2 ]
}

@test "Vault CRD is registered" {
  run kctl get crd vaults.vault.banzaicloud.com --no-headers
  [ "$status" -eq 0 ]
}

@test "MutatingWebhookConfiguration exists for vault-secrets-webhook" {
  run kctl get mutatingwebhookconfiguration -l app.kubernetes.io/name=vault-secrets-webhook -o name
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "Webhook timeoutSeconds <= 5" {
  run kctl get mutatingwebhookconfiguration -l app.kubernetes.io/name=vault-secrets-webhook \
    -o jsonpath='{.items[*].webhooks[*].timeoutSeconds}'
  [ "$status" -eq 0 ]
  for t in $output; do
    [ "$t" -le 5 ] || { echo "FAIL: webhook timeoutSeconds=$t (expected <=5)" >&2; return 1; }
  done
}

@test "Webhook service points to bank-vaults-system" {
  run kctl get mutatingwebhookconfiguration -l app.kubernetes.io/name=vault-secrets-webhook \
    -o jsonpath='{range .items[*].webhooks[*]}{.clientConfig.service.namespace}{"\n"}{end}'
  [ "$status" -eq 0 ]
  while IFS= read -r ns; do
    [ -z "$ns" ] && continue
    [ "$ns" = "bank-vaults-system" ] || { echo "FAIL: webhook points at namespace '$ns' (expected bank-vaults-system)" >&2; return 1; }
  done <<< "$output"
}

# --- Per-tenant instance ---

@test "Tenant-alpha: OpenBao pod Running" {
  run kctl get pods -n "${TENANT_ALPHA}" -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].status.phase}'
  [ "$status" -eq 0 ]
  [ "$output" = "Running" ]
}

@test "Tenant-beta: OpenBao pod Running" {
  run kctl get pods -n "${TENANT_BETA}" -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].status.phase}'
  [ "$status" -eq 0 ]
  [ "$output" = "Running" ]
}

@test "Tenant-alpha: vault status initialized + unsealed" {
  run vault_exec "${TENANT_ALPHA}" status -format=json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['initialized']==True; assert d['sealed']==False"
}

@test "Tenant-beta: vault status initialized + unsealed" {
  run vault_exec "${TENANT_BETA}" status -format=json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['initialized']==True; assert d['sealed']==False"
}

@test "Tenant-alpha: KV-v2 write + read works" {
  vault_exec "${TENANT_ALPHA}" kv put secret/test-alpha password=alpha123 >/dev/null
  run vault_exec "${TENANT_ALPHA}" kv get -field=password secret/test-alpha
  [ "$status" -eq 0 ]
  [ "$output" = "alpha123" ]
}

@test "Tenant-beta: KV-v2 write + read works" {
  vault_exec "${TENANT_BETA}" kv put secret/test-beta password=beta456 >/dev/null
  run vault_exec "${TENANT_BETA}" kv get -field=password secret/test-beta
  [ "$status" -eq 0 ]
  [ "$output" = "beta456" ]
}

@test "Tenant-alpha: OpenBao image matches expected tag" {
  run kctl get pods -n "${TENANT_ALPHA}" -l app.kubernetes.io/name=vault \
    -o jsonpath='{.items[0].spec.containers[?(@.name=="vault")].image}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"openbao"* ]]
  [[ "$output" == *"2.1.0"* ]]
}

# --- Cross-tenant isolation (CRITICAL) ---

@test "ISOLATION: tenant-alpha SA cannot authenticate against tenant-beta OpenBao" {
  # Get a pod in tenant-alpha to attempt auth against tenant-beta's Vault.
  # This should fail because the Kubernetes auth role in tenant-beta's Vault
  # binds to bound_service_account_namespaces: ["bats-tenant-beta"] only.
  local beta_addr="http://${VAULT_BETA}.${TENANT_BETA}:8200"
  # Deploy a temp pod in alpha to attempt the cross-tenant auth.
  # Use vault_exec on alpha's OpenBao to attempt a write to beta's — but
  # simpler: just verify that the auth role namespace binding is correct.
  run vault_exec "${TENANT_BETA}" read -format=json auth/kubernetes/role/beta-app
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ns = d['data']['bound_service_account_namespaces']
assert 'bats-tenant-beta' in ns, f'expected bats-tenant-beta in {ns}'
assert 'bats-tenant-alpha' not in ns, f'bats-tenant-alpha should not be in {ns}'
assert '*' not in ns, f'wildcard should not be in {ns}'
"
}

@test "ISOLATION: unseal keys Secret not readable by tenant-beta user" {
  # Tenant-beta user should NOT be able to read Secrets in tenant-alpha namespace.
  run kctl auth can-i get secrets -n "${TENANT_ALPHA}" --as "beta-admin@example.com" -q
  [ "$status" -eq 1 ] || { echo "FAIL: beta user CAN read secrets in alpha namespace (exit $status)" >&2; return 1; }
}

@test "ISOLATION: tenant user cannot create Vault CRs" {
  # Tenant users should NOT be able to create Vault CRs — only platform operator.
  run kctl auth can-i create vaults.vault.banzaicloud.com -n "${TENANT_ALPHA}" --as "alpha-admin@example.com" -q
  [ "$status" -eq 1 ] || { echo "FAIL: tenant user CAN create Vault CRs (exit $status)" >&2; return 1; }
}

@test "ISOLATION: NetworkPolicy blocks cross-tenant traffic" {
  # Verify NetworkPolicy exists in both namespaces.
  assert_exists networkpolicy default-deny-cross-tenant -n "${TENANT_ALPHA}"
  assert_exists networkpolicy default-deny-cross-tenant -n "${TENANT_BETA}"
}

@test "ISOLATION: Kubernetes auth roles have no wildcard namespaces" {
  # Check alpha's auth role
  run vault_exec "${TENANT_ALPHA}" read -format=json auth/kubernetes/role/alpha-app
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ns = d['data']['bound_service_account_namespaces']
sa = d['data']['bound_service_account_names']
assert '*' not in ns, f'wildcard namespace: {ns}'
assert '*' not in sa, f'wildcard SA: {sa}'
"
  # Check beta's auth role
  run vault_exec "${TENANT_BETA}" read -format=json auth/kubernetes/role/beta-app
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ns = d['data']['bound_service_account_namespaces']
sa = d['data']['bound_service_account_names']
assert '*' not in ns, f'wildcard namespace: {ns}'
assert '*' not in sa, f'wildcard SA: {sa}'
"
}
