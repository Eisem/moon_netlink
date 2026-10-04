# Reproducible demonstrations

Run on Linux with MoonBit's native toolchain, a C compiler, Python 3 and
iproute2. The kernel must permit `unshare -Urn` (user and network namespaces).
Each wrapper checks that its network namespace differs from the caller's and
creates disposable veth interfaces. Missing tools or namespace permissions
produce a nonzero exit; no fallback changes the host network. All subprocesses
have bounded execution time. The namespace and interfaces disappear on success
or failure when its last process exits.

## Container initialization through the SDK

```sh
bash demo/container.sh
```

The MoonBit [SDK example](../examples/configure_veth/main.mbt) uses public
`RouteClient` methods to configure MTU, UP, IPv4/IPv6 addresses and nondefault
routes on a disposable veth. It also checks exclusive duplicates, replacement
and kernel extended diagnostics. The demo independently queries the actual
state, compares it with `ip -j`, then deletes configured resources through the
SDK and checks the resulting MTU/DOWN state. The namespace is released even if
initialization fails partway; this direct SDK example has no atomic rollback.

`ip` is used to create the namespace fixture and to independently validate it.
The MoonBit example sends mutations through RTNetlink, without invoking `ip`.

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

## Protection and a controlled mid-plan failure

```sh
bash demo/failure.sh
```

First, a confirmed loopback change must be rejected before writing; `lo` stays
UP. The fixed [failure configuration](../demo/failure-desired.json) then changes
MTU/UP, adds two addresses and a valid route before requesting an unreachable
gateway. Linux rejects operation six with errno 101. The demo displays the
original structured error, five completed indices, one skipped operation,
reverse compensation and a fresh observation of the restored managed fields.
Final verification must still report the desired state unmet.

Each expected CLI failure must exit nonzero. The wrapper exits zero only when
all failure and recovery assertions pass. It does not deliberately cause kernel
event loss or compensation failure; independent backend tests cover compensation
errors, while `.ci/validate-failures.sh` also restores preexisting resources.

## Concurrent typed monitoring and filtering

```sh
bash demo/monitor.sh
```

Two monitors subscribe and signal ready before the CLI applies the fixed desired
state and then removes the explicitly managed addresses/routes. The demo prints
projections of real Link and IPv4/IPv6 Address/Route events. It requires both
additions and deletions and verifies that the route-only subscription receives
only route events. Every listener and pipe reader is stopped in `finally`, even
when an assertion or command fails.

Netlink multicast is lossy. The CLI exits with a diagnostic on
`EventStreamLost`; consumers must discard their cached state, query a fresh
snapshot and resubscribe. The demo explains this recovery but does not force
kernel event loss. The deterministic overrun fixture is checked separately:

```sh
moon test transport --target native --filter '*overrun*'
```
