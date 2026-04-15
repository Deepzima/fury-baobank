#!/usr/bin/env bats

load 'helpers'

NS=bats-net-test

setup_file() {
  kctl create namespace "${NS}" --dry-run=client -o yaml | kctl apply -f - >/dev/null
  # Deploy two pods on different infra workers using podAntiAffinity.
  # probe-b runs a simple HTTP server (python) that writes a known string to
  # a temp file and serves it. probe-a curls probe-b.
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
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels: { app: probe }
          topologyKey: kubernetes.io/hostname
  tolerations:
    - operator: Exists
  containers:
    - name: probe
      image: curlimages/curl:8.9.1
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
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels: { app: probe }
          topologyKey: kubernetes.io/hostname
  tolerations:
    - operator: Exists
  containers:
    - name: probe
      image: python:3.13-alpine
      command: ["sh", "-c", "echo 'hello-from-b' > /tmp/hello && cd /tmp && python3 -m http.server 8080"]
      readinessProbe:
        tcpSocket: { port: 8080 }
        periodSeconds: 2
EOF
  # Wait for both probes to be Ready (up to 120s — python image pull)
  for p in probe-a probe-b; do
    wait_for 120 "kctl get pod -n ${NS} ${p} -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"
  done
}

teardown_file() {
  kctl delete namespace "${NS}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

@test "probe-a can reach probe-b over the pod network" {
  local b_ip
  b_ip=$(kctl get pod -n "${NS}" probe-b -o jsonpath='{.status.podIP}')
  run kctl exec -n "${NS}" probe-a -- curl -sf --max-time 5 "http://${b_ip}:8080/hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello-from-b"* ]]
}

@test "DNS resolution works inside the cluster" {
  # curlimages/curl doesn't ship nslookup/dig; use getent
  run kctl exec -n "${NS}" probe-a -- getent hosts kubernetes.default.svc.cluster.local
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "probes are on two different nodes (spread across infra workers)" {
  local node_a node_b
  node_a=$(kctl get pod -n "${NS}" probe-a -o jsonpath='{.spec.nodeName}')
  node_b=$(kctl get pod -n "${NS}" probe-b -o jsonpath='{.spec.nodeName}')
  [ "$node_a" != "$node_b" ]
}
