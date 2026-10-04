# MoonNetlink

MoonNetlink is a typed RTNetlink SDK and declarative Linux network state
toolkit for MoonBit.

The SDK currently supports typed Link/Address/Route/Neighbor queries,
Link UP/DOWN and MTU changes, IPv4/IPv6 address and unicast route add/delete,
and typed multicast events. Protocol encoding and decoding are implemented
in MoonBit; the C shim only opens and transfers the Linux socket. SDK queries
and mutations do not invoke `ip`. The state package provides owned snapshots,
strict desired configuration parsing, scoped differences and deterministic
plans. The planning CLI defaults to dry-run and checks critical-resource
protections. Confirmed execution of plans remains unfinished.

Source files to commit and local files to exclude are listed in
[docs/repository.md](./docs/repository.md).

The native descriptor ownership and fail-closed datagram policy are documented
in [docs/transport.md](./docs/transport.md).
The transport-independent message, attribute, and control-message rules are
documented in [docs/core.md](./docs/core.md).
Typed RTNetlink model coverage and validation rules are documented in
[docs/route.md](./docs/route.md).
The query/event CLI and deterministic JSON contract are documented in
[docs/cli.md](./docs/cli.md).
The reproducible Linux comparison with `ip -j` is documented in
[docs/differential.md](./docs/differential.md).
The desired schema, snapshots and pure planning APIs are documented in
[docs/state.md](./docs/state.md).

## CLI

Build and test from a checkout with the MoonBit toolchain and a C compiler:

```sh
git clone https://github.com/Eisem/moon_netlink.git
cd moon_netlink
moon update
moon check --target native
moon test --target native
```

Run the following commands on Linux:

```sh
moon run --target native cmd/moonnet -- link show
moon run --target native cmd/moonnet -- address show --json
moon run --target native cmd/moonnet -- route show
moon run --target native cmd/moonnet -- neighbor show --json
moon run --target native cmd/moonnet -- watch all --jsonl
moon run --target native cmd/moonnet -- snapshot
moon run --target native cmd/moonnet -- plan desired.json --json
moon run --target native cmd/moonnet -- apply desired.json --json  # dry-run
```

All four commands sort their output deterministically. JSON uses canonical
address text, ordinary numbers for present values, and `null` for absent ones.

## SDK query examples

On Linux with MoonBit and a C compiler:

```sh
moon run --target native examples/inspect_links
moon run --target native examples/inspect_addresses
moon run --target native examples/inspect_routes
moon run --target native examples/inspect_neighbors
```

Expected output contains a line for the loopback interface named `lo`, at least
one typed address from `RTM_GETADDR`, typed routes from `RTM_GETROUTE`, and a
successful `RTM_GETNEIGH` dump (which may contain zero entries on an idle host).

## Platform

MoonNetlink targets Linux on MoonBit's native backend. Queries and monitoring
normally run without root; mutations require network administration privileges
in the process's network namespace. Pure codec tests also run on Windows;
opening a Linux route socket there returns `UnsupportedPlatform`.

## Isolated mutation and monitor example

On Linux with MoonBit, a C compiler, Python 3, iproute2, and permitted user/network
namespaces:

```sh
bash .ci/validate-mutations.sh
```

This creates a disposable veth pair inside `unshare -Urn`, runs
`examples/configure_veth` to configure MTU, UP state, IPv4/IPv6 addresses and
routes, verifies exclusive/replace behavior and kernel diagnostics, compares
with `ip -j`, and removes the configuration. Concurrent `watch --jsonl` streams
verify Link, Address, Route and Neighbor events. The namespace and processes
are cleaned up on success or failure. No host interface is modified.

The example requires an explicit `--yes`; use it only on a disposable interface
inside a temporary namespace. The SDK applies mutations directly. Default
dry-run and loopback/default-route checks are available in the planning CLI;
confirmed plan execution is not available yet. Direct SDK mutations remain
the caller's responsibility.

## License

MIT
