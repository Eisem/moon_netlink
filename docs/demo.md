# Reproducible demonstrations

Run on Linux with MoonBit's native toolchain, a C compiler, Python 3 and
iproute2. The kernel must permit `unshare -Urn` (user and network namespaces).
Each wrapper checks that its network namespace differs from the caller's and
creates disposable veth interfaces. Missing tools or namespace permissions
produce a nonzero exit; no fallback changes the host network. All subprocesses
have bounded execution time. The namespace and interfaces disappear on success
or failure when its last process exits.

## Snapshot, plan and apply

From the repository root:

```sh
moon update
bash demo/reconcile.sh
```

The script uses the fixed [desired configuration](../demo/desired.json) and the
public `moonnet` CLI. Its output follows the actual workflow:

1. Initial snapshot and independently observed veth configuration.
2. Six ordered operations: MTU, UP, IPv4/IPv6 addresses and nondefault routes.
   Plan and unconfirmed apply agree; the configuration remains unchanged.
3. Explicit `apply --yes`, its acknowledged operations and final verification.
4. Final snapshot and query comparison with `ip -j`.
5. Empty second plan and successful second apply with zero operations.
6. Namespace released.

Assertions make any unexpected outcome fail the demo. Snapshot summaries show
object counts; full canonical snapshots are available with `moonnet snapshot`.
The query comparison uses the documented typed fields; extra kernel neighbor
entries can exist beyond the subset listed by `ip -j`. Address state and counts
can also vary during IPv6 duplicate-address detection.

This workflow demonstrates supported managed fields and fresh observation.
It does not make kernel mutations atomic or reproduce every kernel metadata
field; see [reconciliation limits](reconcile.md).
