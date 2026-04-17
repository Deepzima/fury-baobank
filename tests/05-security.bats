#!/usr/bin/env bats

load 'helpers'

@test "kubeconfig permissions are 0600" {
  local kc="${KUBECONFIG:-${HOME}/.kube/config}"
  [ -f "$kc" ]
  local perm
  perm=$(stat -f "%A" "$kc" 2>/dev/null || stat -c "%a" "$kc")
  [ "$perm" = "600" ]
}

@test "cluster context matches fury-baobank (prevents accidental prod use)" {
  run kubectl config current-context
  [ "$status" -eq 0 ]
  [ "$output" = "${CONTEXT}" ]
}

@test "only Cilium-related pods are privileged in kube-system" {
  # Pods with privileged:true; fail the test if any non-Cilium pod appears.
  run kctl get pods -n kube-system -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].securityContext.privileged}{"\n"}{end}'
  [ "$status" -eq 0 ]
  # Cilium-related pods allowed: names starting with "cilium" or "hubble"
  while IFS=$'\t' read -r name privileged; do
    if [[ "$privileged" == *"true"* ]]; then
      if [[ ! "$name" =~ ^(cilium|hubble) ]]; then
        echo "FAIL: unexpected privileged pod ${name} (expected only cilium-*/hubble-*)" >&2
        return 1
      fi
    fi
  done <<< "$output"
}

@test "Kind port mappings bind to 127.0.0.1 only (no 0.0.0.0)" {
  # Check the actual Kind container port publishing — should be 127.0.0.1:X->X
  run docker ps --filter "name=${CLUSTER_NAME}" --format '{{.Ports}}'
  [ "$status" -eq 0 ]
  if echo "$output" | grep -E '(^|[^0-9])0\.0\.0\.0:'; then
    echo "FAIL: found 0.0.0.0 binding — expected only 127.0.0.1" >&2
    return 1
  fi
}

# --- Capsule tenancy boundary checks (FD-002 threat model rec #11) ---

@test "Capsule ValidatingWebhookConfiguration exists (tenancy boundary)" {
  run kctl get validatingwebhookconfiguration -l app.kubernetes.io/name=capsule -o name
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "No rogue Capsule webhook points outside capsule-system" {
  # Every webhook client config for a Capsule-owned webhook must point at a
  # service inside capsule-system. An attacker who swaps the service target
  # could intercept admission reviews.
  run kctl get validatingwebhookconfiguration -l app.kubernetes.io/name=capsule \
    -o jsonpath='{range .items[*].webhooks[*]}{.clientConfig.service.namespace}{"\n"}{end}'
  [ "$status" -eq 0 ]
  while IFS= read -r ns; do
    [ -z "$ns" ] && continue
    [ "$ns" = "capsule-system" ] || { echo "FAIL: webhook points at namespace '$ns' (expected capsule-system)" >&2; return 1; }
  done <<< "$output"
}
