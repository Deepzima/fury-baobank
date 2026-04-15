#!/usr/bin/env bats

load 'helpers'

NS=bats-net-test

setup_file() {
  kctl create namespace "${NS}" --dry-run=client -o yaml | kctl apply -f - >/dev/null
  # Deploy two pods on different infra workers (via node selector) and a Service
  cat <<EOF | kctl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: probe-a
  namespace: ${NS}
  labels: { app: probe, which: a }
spec:
  nodeSelector:
    node-role.fury.io/infra: "true"
  tolerations:
    - operator: Exists
  containers:
    - name: probe
      image: busybox:stable
      command: ["sh", "-c", "sleep 3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: probe-b
  namespace: ${NS}
  labels: { app: probe, which: b }
spec:
  nodeSelector:
    node-role.fury.io/infra: "true"
  tolerations:
    - operator: Exists
  containers:
    - name: probe
      image: busybox:stable
      command: ["sh", "-c", "httpd -f -p 8080 -h /tmp"]
      readinessProbe:
        tcpSocket: { port: 8080 }
EOF
  # Wait for both probes to be Ready (up to 60s)
  for p in probe-a probe-b; do
    wait_for 60 "kctl get pod -n ${NS} ${p} -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"
  done
}

teardown_file() {
  kctl delete namespace "${NS}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

@test "probe-a can reach probe-b over the pod network" {
  local b_ip
  b_ip=$(kctl get pod -n "${NS}" probe-b -o jsonpath='{.status.podIP}')
  run kctl exec -n "${NS}" probe-a -- wget -qO- --timeout=5 "http://${b_ip}:8080/"
  [ "$status" -eq 0 ]
}

@test "DNS resolution works inside the cluster" {
  run kctl exec -n "${NS}" probe-a -- nslookup kubernetes.default.svc.cluster.local
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Address"
}

@test "probes are on two different nodes (spread across infra workers)" {
  local node_a node_b
  node_a=$(kctl get pod -n "${NS}" probe-a -o jsonpath='{.spec.nodeName}')
  node_b=$(kctl get pod -n "${NS}" probe-b -o jsonpath='{.spec.nodeName}')
  [ "$node_a" != "$node_b" ]
}
