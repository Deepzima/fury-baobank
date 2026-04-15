#!/usr/bin/env bats

load 'helpers'

@test "Kind cluster exists" {
  kind get clusters | grep -q "^${CLUSTER_NAME}$"
}

@test "Cluster has exactly 3 nodes" {
  run kctl get nodes --no-headers
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 3 ]
}

@test "1 control-plane + 2 workers" {
  # control-plane label value is empty string "" when set (presence = role).
  # Count nodes that HAVE the label vs those that don't.
  run kctl get nodes -l node-role.kubernetes.io/control-plane -o name
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]

  # Workers = all nodes minus the control-plane (use the infra label we set).
  run kctl get nodes -l node-role.fury.io/infra=true -o name
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "Worker nodes labeled node-role.fury.io/infra=true" {
  run kctl get nodes -l node-role.fury.io/infra=true -o name
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "Cluster context is kind-fury-baobank" {
  run kubectl config current-context
  [ "$status" -eq 0 ]
  [ "$output" = "${CONTEXT}" ]
}
