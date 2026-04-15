# Hubble queries — starter kit

Three queries you can run against the lab's Cilium/Hubble install to get a feel for the data plane.

All examples assume you have run `mise run hubble` (port-forward) in one terminal, and you have the `hubble` CLI installed locally (`brew install cilium/cilium/hubble`).

Point the CLI at the relay:

```bash
export HUBBLE_SERVER=127.0.0.1:12000   # set when port-forward is active
```

## 1. All pod-to-pod flows in the last minute

Shows which pods are talking to each other, regardless of namespace or port.

```bash
hubble observe --since 1m --type trace
```

What you're looking at: source pod, destination pod, L4 protocol, and verdict (ALLOWED / DROPPED / ERROR). If you see nothing, your cluster is very quiet — try creating a test workload.

## 2. Cross-namespace denies

Shows any traffic that was explicitly dropped by a `CiliumNetworkPolicy`. Useful the moment you start enforcing policies and want to confirm they're applying.

```bash
hubble observe \
  --verdict DROPPED \
  --not --from-namespace kube-system \
  --not --to-namespace kube-system
```

What you're looking at: denies between your own namespaces (kube-system denies are usually internal Cilium chatter and would drown out user-space events).

## 3. DNS lookups from a specific pod

Shows the DNS queries a pod is making — helpful to debug connectivity issues that look like "my app can't reach `postgres.db.svc`".

```bash
hubble observe \
  --pod default/my-app \
  --protocol dns
```

Requires L7 DNS visibility enabled on the relevant pod via a `CiliumNetworkPolicy` with `rules.dns`. L7 visibility is opt-in per namespace — we don't enable it globally to avoid leaking sensitive headers in flow logs.

---

## Notes

- **L7 visibility is opt-in.** Adding `rules.http` or `rules.dns` to a `CiliumNetworkPolicy` tells Cilium to proxy that traffic through Envoy and surface L7 metadata in Hubble. Without it, you only see L3/L4 (IPs, ports, verdicts).
- **Flow retention is in-memory.** The relay keeps a rolling buffer; old flows are dropped. For long-term observability use Hubble → Prometheus integration (not in scope for this lab).
- **mTLS.** The relay refuses unauthenticated gRPC (see `scripts/hubble-mtls-check.sh`). When running `hubble observe` locally through the port-forward you're hitting the relay via loopback — the CLI uses the local cluster's client cert automatically when present.
