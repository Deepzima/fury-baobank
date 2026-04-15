#!/usr/bin/env bats

load 'helpers'

@test "hubble-ui Service exists" {
  assert_exists svc -n kube-system hubble-ui
}

@test "hubble-relay Service exists" {
  assert_exists svc -n kube-system hubble-relay
}

@test "hubble-relay pod is Ready" {
  wait_for 60 'kctl get pods -n kube-system -l k8s-app=hubble-relay -o jsonpath="{.items[*].status.conditions[?(@.type==\"Ready\")].status}" | grep -q True'
}

@test "Hubble mTLS is enforced (relay rejects unauthenticated gRPC)" {
  run bash "${BATS_TEST_DIRNAME}/../scripts/hubble-mtls-check.sh"
  [ "$status" -eq 0 ]
}

@test "Hubble UI port-forward returns HTTP 200 on 127.0.0.1" {
  # Start port-forward in background, query, then stop
  kctl port-forward -n kube-system svc/hubble-ui 12001:80 --address 127.0.0.1 >/dev/null 2>&1 &
  local pf_pid=$!
  sleep 2
  run curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1:12001/
  local code="${output}"
  kill "${pf_pid}" 2>/dev/null || true
  wait "${pf_pid}" 2>/dev/null || true
  [ "$code" = "200" ] || [ "$code" = "302" ]
}
