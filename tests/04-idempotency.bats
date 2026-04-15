#!/usr/bin/env bats

load 'helpers'

# These tests assume the cluster is already up (mise run up was executed).
# They verify that re-running the task does not break or churn resources.

@test "mise run up is idempotent on an existing cluster" {
  run mise run up
  [ "$status" -eq 0 ]
  # Must mention the skip path, not a fresh create
  echo "$output" | grep -q "already exists"
}

@test "mise run install-cni does not error when Cilium is already installed" {
  run mise run install-cni
  [ "$status" -eq 0 ]
}

@test "node count is still 3 after re-running up" {
  run kctl get nodes --no-headers
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 3 ]
}

@test "Cilium pod count is still 3 after re-running install-cni" {
  run kctl get pods -n kube-system -l k8s-app=cilium --no-headers
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 3 ]
}
