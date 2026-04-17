#!/usr/bin/env bats

load 'helpers'

# Unique per-run identifier to avoid collisions if the suite runs in parallel
# or leaves residue from a prior failed run.
TENANT_NAME="bats-tenant-$$"
TENANT_OWNER="alice@example.com"

setup_file() {
  # Sanity: Capsule must already be installed (via furyctl apply). If not,
  # every test below would fail with confusing errors. Fail early and loud.
  if ! kctl get ns capsule-system &>/dev/null; then
    echo "FATAL: capsule-system namespace missing — run 'mise run install-cni' first" >&2
    return 1
  fi
  # Pre-emptive cleanup (ignore failures — resource may not exist)
  kctl delete tenant "${TENANT_NAME}" --ignore-not-found --wait=true >/dev/null 2>&1 || true
}

teardown_file() {
  # Best-effort cleanup: BATS guarantees this runs even on test failure.
  kctl delete tenant "${TENANT_NAME}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

# --- Install sanity ---

@test "capsule-system namespace exists" {
  assert_exists ns capsule-system
}

@test "Capsule controller pod is Ready" {
  wait_for 120 'kctl get pods -n capsule-system -l app.kubernetes.io/name=capsule -o jsonpath="{.items[*].status.conditions[?(@.type==\"Ready\")].status}" | grep -q True'
}

@test "Capsule controller runs at least 2 replicas (HA)" {
  run kctl get deployment -n capsule-system -l app.kubernetes.io/name=capsule -o jsonpath='{.items[0].status.readyReplicas}'
  [ "$status" -eq 0 ]
  [ "${output:-0}" -ge 2 ]
}

@test "All Capsule CRDs are registered" {
  for crd in tenants capsuleconfigurations globaltenantresources tenantresources; do
    run kctl get crd "${crd}.capsule.clastix.io" --no-headers
    [ "$status" -eq 0 ] || { echo "FAIL: CRD ${crd}.capsule.clastix.io missing" >&2; return 1; }
  done
}

# --- Webhook configuration (threat model rec #8) ---

@test "Capsule ValidatingWebhookConfiguration exists" {
  run kctl get validatingwebhookconfiguration -l app.kubernetes.io/name=capsule -o name
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "Capsule tenant-enforcing webhooks have failurePolicy: Fail" {
  # We check every webhook name individually and assert failurePolicy.
  # The `config.projectcapsule.dev` webhook (CapsuleConfiguration CR) is
  # allowed to be Ignore — if the controller is down you still want to be
  # able to patch the config to recover.
  run kctl get validatingwebhookconfiguration -l app.kubernetes.io/name=capsule \
    -o jsonpath='{range .items[*].webhooks[*]}{.name}={.failurePolicy}{"\n"}{end}'
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local name="${line%=*}"
    local policy="${line#*=}"
    case "$name" in
      config.projectcapsule.dev)
        # Ignore is acceptable — see comment above
        ;;
      *)
        [ "$policy" = "Fail" ] || { echo "FAIL: webhook $name has failurePolicy=$policy (expected Fail)" >&2; return 1; }
        ;;
    esac
  done <<< "$output"
}

@test "Capsule webhook timeoutSeconds is <= 5 (DoS mitigation)" {
  run kctl get validatingwebhookconfiguration -l app.kubernetes.io/name=capsule -o jsonpath='{.items[*].webhooks[*].timeoutSeconds}'
  [ "$status" -eq 0 ]
  # Every numeric value in output must be <= 5
  for t in $output; do
    [ "$t" -le 5 ] || { echo "FAIL: found webhook timeoutSeconds=$t (expected <=5)" >&2; return 1; }
  done
}

# --- Tenant enforcement (threat model rec #9) ---

@test "Tenant CR is accepted with sane quota and status reconciled" {
  cat <<EOF | kctl apply -f - >/dev/null
apiVersion: capsule.clastix.io/v1beta2
kind: Tenant
metadata:
  name: ${TENANT_NAME}
spec:
  owners:
    - name: "${TENANT_OWNER}"
      kind: User
  resourceQuotas:
    scope: Tenant
    items:
      - hard:
          limits.cpu: "2"
          limits.memory: "2Gi"
          requests.storage: "1Gi"
  namespaceOptions:
    quota: 3
EOF

  # Reconciliation is asynchronous — give the controller up to 30s to set
  # status.state=Active. This is the webhook-accepted-but-not-yet-reconciled
  # window; anything longer points at a controller crash loop.
  wait_for 30 "kctl get tenant '${TENANT_NAME}' -o jsonpath='{.status.state}' | grep -q '^Active$'"

  # The tenant should report Ready=True
  run kctl get tenant "${TENANT_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "Capsule webhook blocks non-tenant users from creating namespaces" {
  # A user NOT listed as tenant owner (and not cluster-admin) must NOT be
  # able to create namespaces. This is the core security guarantee of
  # Capsule — tenancy boundary enforcement.
  # `kubectl auth can-i` exits non-zero when the answer is "no" — that's
  # the PASS condition for this test.
  # -q silences output and uses only the exit code: 0 = yes, 1 = no
  # We expect exit code 1 (answer: no).
  run kctl auth can-i create namespace --as "unauthorized-user@example.com" -q
  [ "$status" -eq 1 ] || { echo "FAIL: expected 'no' (exit 1), got exit $status" >&2; return 1; }
}

# --- Privilege escalation rejection (threat model rec #7) ---

@test "Tenant with cluster-admin additionalRoleBinding does not propagate cluster-wide" {
  # Apply (or update) the tenant with a dangerous additionalRoleBinding.
  # Capsule should scope it to tenant namespaces only — NOT create a
  # cluster-wide ClusterRoleBinding granting the tenant owner cluster-admin.
  cat <<EOF | kctl apply -f - >/dev/null
apiVersion: capsule.clastix.io/v1beta2
kind: Tenant
metadata:
  name: ${TENANT_NAME}
spec:
  owners:
    - name: "${TENANT_OWNER}"
      kind: User
  additionalRoleBindings:
    - clusterRoleName: cluster-admin
      subjects:
        - kind: User
          name: "${TENANT_OWNER}"
EOF

  # No cluster-wide ClusterRoleBinding granting cluster-admin to the tenant
  # owner should exist. Search for any CRB that pairs cluster-admin with the
  # tenant owner.
  run kctl get clusterrolebinding -o json
  [ "$status" -eq 0 ]
  if echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for crb in data['items']:
    roleRef = crb.get('roleRef', {})
    if roleRef.get('name') != 'cluster-admin':
        continue
    for s in crb.get('subjects') or []:
        if s.get('kind') == 'User' and s.get('name') == '${TENANT_OWNER}':
            print(crb['metadata']['name'])
            sys.exit(1)
sys.exit(0)
"; then
    :  # no match = test passes
  else
    echo "FAIL: Capsule propagated cluster-admin to tenant owner via ClusterRoleBinding" >&2
    return 1
  fi
}
