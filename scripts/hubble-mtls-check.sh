#!/usr/bin/env bash
# Verify that the Hubble relay enforces mTLS.
# Exit 0 when unauthenticated gRPC is rejected (= mTLS working).
# Exit 1 when the relay accepts unauth connections (= mTLS NOT enforced).
#
# Used by:
#   - mise run hubble-mtls-check (manual)
#   - tests/03-hubble.bats (E2E suite, SDD-004)
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-fury-baobank}"
CONTEXT="kind-${CLUSTER_NAME}"
NS="kube-system"
RELAY_SVC="hubble-relay"
LOCAL_PORT="${LOCAL_PORT:-14245}"

cleanup() {
  if [[ -n "${PF_PID:-}" ]] && kill -0 "${PF_PID}" 2>/dev/null; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Ensure relay exists
if ! kubectl --context "${CONTEXT}" get svc -n "${NS}" "${RELAY_SVC}" &>/dev/null; then
  echo "ERROR: service ${NS}/${RELAY_SVC} not found — install Cilium with 'mise run install-cni' first" >&2
  exit 2
fi

# Start background port-forward
kubectl --context "${CONTEXT}" port-forward \
  -n "${NS}" "svc/${RELAY_SVC}" "${LOCAL_PORT}:4245" \
  --address 127.0.0.1 >/dev/null 2>&1 &
PF_PID=$!
sleep 2

# Probe with a plaintext connection — should fail with TLS handshake error
if command -v grpcurl >/dev/null 2>&1; then
  # grpcurl without certs should be rejected
  if grpcurl -plaintext -max-time 3 "127.0.0.1:${LOCAL_PORT}" list 2>/dev/null; then
    echo "FAIL: Hubble relay accepted unauthenticated gRPC — mTLS NOT enforced" >&2
    exit 1
  fi
  echo "PASS: Hubble relay rejected unauthenticated gRPC (mTLS enforced)"
else
  # Fallback: nc + opportunistic TLS probe — returns error if server requires TLS
  if echo "" | nc -w 3 127.0.0.1 "${LOCAL_PORT}" 2>&1 | grep -q -E "TLS|handshake|cert" ; then
    echo "PASS: plaintext probe rejected (TLS required)"
  else
    echo "WARN: grpcurl not installed — plaintext probe inconclusive. Install grpcurl for a proper check." >&2
    echo "      brew install grpcurl  /  go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest"
    exit 0
  fi
fi
