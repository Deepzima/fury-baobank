#!/usr/bin/env bats

load 'helpers'

@test "Cilium agents exist on every node" {
  run kctl get pods -n kube-system -l k8s-app=cilium --no-headers
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 3 ]
}

@test "All Cilium agents are Ready" {
  wait_for 120 'kctl get pods -n kube-system -l k8s-app=cilium -o jsonpath="{.items[*].status.conditions[?(@.type==\"Ready\")].status}" | grep -v False | grep -q True'
  run kctl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q False
}

@test "kube-proxy DaemonSet is absent (Cilium replaced it)" {
  assert_absent daemonset -n kube-system kube-proxy
}

@test "cilium-config has kube-proxy-replacement=true" {
  run kctl get cm -n kube-system cilium-config -o jsonpath='{.data.kube-proxy-replacement}'
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "cilium-operator is running" {
  run kctl get deployment -n kube-system cilium-operator -o jsonpath='{.status.readyReplicas}'
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
