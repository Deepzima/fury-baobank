#!/usr/bin/env bash
# Shared helpers for the fury-baobank BATS suites.
# Loaded by every test file via `load 'helpers'`.

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-fury-baobank}"
CONTEXT="kind-${CLUSTER_NAME}"

kctl() {
  kubectl --context "${CONTEXT}" "$@"
}

# wait_for <timeout_seconds> <bash_predicate_command>
# Retries the predicate every second until it returns 0 or the timeout elapses.
wait_for() {
  local timeout="$1"; shift
  local elapsed=0
  until eval "$@"; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [[ "${elapsed}" -ge "${timeout}" ]]; then
      echo "wait_for: predicate '$*' did not become true within ${timeout}s" >&2
      return 1
    fi
  done
}

# Assert that a kubectl resource exists.
assert_exists() {
  kctl get "$@" &>/dev/null
}

# Assert that a kubectl resource does NOT exist.
assert_absent() {
  ! kctl get "$@" &>/dev/null
}
