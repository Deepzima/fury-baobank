#!/usr/bin/env bats

# PKI/CA engine tests (FD-005).
# Validates: two-tier CA, K8s-compatible certs, revocation + CRL.

BAOBANK_CONTEXT="kind-fury-baobank"
TENANT_NS="scen-acme"
VAULT_NAME="reevo-ob-id-acme"

vault_cmd() {
  local token
  token=$(kubectl --context "${BAOBANK_CONTEXT}" get secret -n "${TENANT_NS}" \
    "${VAULT_NAME}-unseal-keys" -o jsonpath='{.data.vault-root}' | base64 -d)
  local pod
  pod=$(kubectl --context "${BAOBANK_CONTEXT}" get pods -n "${TENANT_NS}" \
    -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')
  kubectl --context "${BAOBANK_CONTEXT}" exec -n "${TENANT_NS}" "${pod}" -c vault -- \
    env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${token}" vault "$@"
}

setup_file() {
  # Fail-fast: PKI engines must be enabled
  if ! vault_cmd secrets list -format=json 2>/dev/null | grep -q "pki-root/"; then
    echo "FATAL: pki-root/ engine not found — run 'mise run scen:pki-ca:setup' first" >&2
    return 1
  fi
}

# --- CA chain ---

@test "PKI Root CA engine is enabled" {
  run vault_cmd secrets list -format=json
  [ "$status" -eq 0 ]
  [[ "$output" == *"pki-root/"* ]]
}

@test "PKI Intermediate CA engine is enabled" {
  run vault_cmd secrets list -format=json
  [ "$status" -eq 0 ]
  [[ "$output" == *"pki-k8s/"* ]]
}

@test "Root CA certificate exists" {
  run vault_cmd read -format=json pki-root/cert/ca
  [ "$status" -eq 0 ]
  [[ "$output" == *"BEGIN CERTIFICATE"* ]]
}

@test "Intermediate CA is signed by Root CA (chain validates)" {
  # Get both certs
  local root_cert inter_cert
  root_cert=$(vault_cmd read -field=certificate pki-root/cert/ca)
  inter_cert=$(vault_cmd read -field=certificate pki-k8s/cert/ca)

  # Write to temp files and verify chain
  echo "$root_cert" > /tmp/test-root-ca.pem
  echo "$inter_cert" > /tmp/test-inter-ca.pem
  run openssl verify -CAfile /tmp/test-root-ca.pem /tmp/test-inter-ca.pem
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "Root CA has no roles (offline — only signs Intermediates)" {
  run vault_cmd list pki-root/roles 2>&1
  # Should fail (no roles) or return empty
  [[ "$output" == *"No value found"* ]] || [[ "$output" == *"no entries"* ]] || [ "$status" -ne 0 ]
}

# --- Roles exist ---

@test "Role k8s-apiserver exists on pki-k8s/" {
  run vault_cmd read pki-k8s/roles/k8s-apiserver
  [ "$status" -eq 0 ]
}

@test "Role k8s-kubelet exists on pki-k8s/" {
  run vault_cmd read pki-k8s/roles/k8s-kubelet
  [ "$status" -eq 0 ]
}

@test "Role k8s-etcd exists on pki-k8s/" {
  run vault_cmd read pki-k8s/roles/k8s-etcd
  [ "$status" -eq 0 ]
}

@test "Role k8s-front-proxy exists on pki-k8s/" {
  run vault_cmd read pki-k8s/roles/k8s-front-proxy
  [ "$status" -eq 0 ]
}

# --- Cert issuance: apiserver ---

@test "Issue apiserver cert with correct SANs" {
  run vault_cmd write -format=json pki-k8s/issue/k8s-apiserver \
    common_name="kubernetes" \
    alt_names="kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster.local" \
    ip_sans="10.96.0.1,127.0.0.1" \
    ttl=24h
  [ "$status" -eq 0 ]

  # Parse and validate SANs
  local cert
  cert=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['certificate'])")
  echo "$cert" | openssl x509 -noout -text > /tmp/test-apiserver-cert.txt

  # Check SANs
  grep -q "DNS:kubernetes.default.svc.cluster.local" /tmp/test-apiserver-cert.txt
  grep -q "IP Address:10.96.0.1" /tmp/test-apiserver-cert.txt
}

@test "Apiserver cert has Server Auth EKU" {
  cat /tmp/test-apiserver-cert.txt | grep -q "TLS Web Server Authentication"
}

@test "Apiserver cert key size >= 2048" {
  run grep "Public-Key:" /tmp/test-apiserver-cert.txt
  [[ "$output" == *"2048"* ]] || [[ "$output" == *"4096"* ]]
}

@test "Apiserver cert TTL <= 24h" {
  # Check Not After is within 25h from now (allowing 1h margin)
  local not_after
  not_after=$(cat /tmp/test-apiserver-cert.txt | grep "Not After" | sed 's/.*Not After : //')
  local not_after_epoch
  not_after_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "${not_after}" +%s 2>/dev/null || date -d "${not_after}" +%s)
  local now_epoch
  now_epoch=$(date +%s)
  local diff=$(( not_after_epoch - now_epoch ))
  [ "$diff" -le 90000 ]  # 25h in seconds
}

# --- Cert issuance: kubelet ---

@test "Issue kubelet cert with correct CN and O" {
  run vault_cmd write -format=json pki-k8s/issue/k8s-kubelet \
    common_name="system:node:worker-1" \
    ttl=24h
  [ "$status" -eq 0 ]

  local cert
  cert=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['certificate'])")
  echo "$cert" | openssl x509 -noout -text > /tmp/test-kubelet-cert.txt

  grep -q "Subject.*CN.*=.*system:node:worker-1" /tmp/test-kubelet-cert.txt
  grep -q "Subject.*O.*=.*system:nodes" /tmp/test-kubelet-cert.txt
}

@test "Kubelet cert has Client Auth EKU" {
  cat /tmp/test-kubelet-cert.txt | grep -q "TLS Web Client Authentication"
}

# --- Cert issuance: etcd ---

@test "Issue etcd cert with Server + Client Auth" {
  run vault_cmd write -format=json pki-k8s/issue/k8s-etcd \
    common_name="etcd" \
    alt_names="localhost" \
    ip_sans="127.0.0.1" \
    ttl=24h
  [ "$status" -eq 0 ]

  local cert
  cert=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['certificate'])")
  echo "$cert" | openssl x509 -noout -text > /tmp/test-etcd-cert.txt

  grep -q "TLS Web Server Authentication" /tmp/test-etcd-cert.txt
  grep -q "TLS Web Client Authentication" /tmp/test-etcd-cert.txt
}

# --- Cert issuance: front-proxy ---

@test "Issue front-proxy cert with Client Auth only" {
  run vault_cmd write -format=json pki-k8s/issue/k8s-front-proxy \
    common_name="front-proxy-client" \
    ttl=24h
  [ "$status" -eq 0 ]

  local cert
  cert=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['certificate'])")
  echo "$cert" | openssl x509 -noout -text > /tmp/test-fp-cert.txt

  grep -q "TLS Web Client Authentication" /tmp/test-fp-cert.txt
  ! grep -q "TLS Web Server Authentication" /tmp/test-fp-cert.txt
}

# --- Chain validation ---

@test "Issued cert chain validates: Root → Intermediate → apiserver leaf" {
  local leaf_cert
  leaf_cert=$(vault_cmd write -format=json pki-k8s/issue/k8s-apiserver \
    common_name="kubernetes" ttl=1h | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['certificate'])")
  echo "$leaf_cert" > /tmp/test-leaf.pem

  run openssl verify -CAfile /tmp/test-root-ca.pem -untrusted /tmp/test-inter-ca.pem /tmp/test-leaf.pem
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# --- Revocation + CRL ---

@test "Revoke a cert and verify revocation succeeds" {
  # Issue a cert
  local serial
  serial=$(vault_cmd write -format=json pki-k8s/issue/k8s-apiserver \
    common_name="kubernetes" ttl=1h | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['serial_number'])")

  # Revoke it — the success of this command proves revocation works
  run vault_cmd write pki-k8s/revoke serial_number="${serial}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"revocation_time"* ]]
}

@test "CRL endpoint is accessible" {
  # CRL should be fetchable via the Vault API
  run vault_cmd read -format=json pki-k8s/crl/rotate
  [ "$status" -eq 0 ]
}

# --- Security: unauthorized SAN rejection ---

@test "SECURITY: issuing cert with unauthorized SAN fails" {
  # Try to issue an apiserver cert with evil.com SAN — should be rejected
  run vault_cmd write pki-k8s/issue/k8s-apiserver \
    common_name="kubernetes" \
    alt_names="evil.com" \
    ttl=1h
  [ "$status" -ne 0 ]
}
