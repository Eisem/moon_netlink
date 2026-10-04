# Query and event CLI

The `cmd/moonnet` executable exposes the four Phase 2 typed queries:

```text
moonnet link show [--json]
moonnet address show [--json]
moonnet route show [--json]
moonnet neighbor show [--json]
```

From the source tree, use `moon run --target native cmd/moonnet --` before the
arguments. The commands are read-only and require Linux/native, but do not
normally require elevated privileges.

Human output is tab-separated and intended for inspection. `--json` emits one
JSON array with canonical IP/MAC strings, explicit `null` for absent values,
and ordinary JSON numbers for present numeric fields.

Output order is deterministic:

- Link: interface index, then name;
- Address: interface index, family, address, then prefix length;
- Route: family, table, destination, prefix, output interface, then gateway;
- Neighbor: interface index, family, destination, then link-layer address.

Route tie-breakers include source prefix length, preferred source, input
interface, protocol, scope, type, TOS and flags. All fields rendered in Route
JSON participate in its ordering, so reversing the kernel's record order does
not change the output. Unknown attributes are preserved in the SDK but are
not emitted by this CLI.

## Watch

```text
moonnet watch [link|address|route|neighbor|all] [--jsonl]
```

The default filter is `all`; `--jsonl` can appear before or after the filter.
Duplicate filters/options and unknown arguments fail with a nonzero exit code.
`watch` opens an independent multicast socket and streams until cancelled or
an error occurs. It writes `moonnet watch: ready` to stderr after subscribing,
so scripts can generate events without guessing a startup delay.

JSONL writes one complete JSON object per line immediately, with two keys:

```json
{"event":"address.added","object":{"family":"ipv4","interface_index":7,"interface_name":null,"prefix_length":24,"scope":0,"local_address":"192.0.2.10","address":"192.0.2.10","label":null,"flags":0}}
```

Event names are `link.changed`, `link.deleted`, `address.added`,
`address.deleted`, `route.added`, `route.deleted`, `neighbor.changed`,
`neighbor.deleted`, and `unknown`. Known objects use the corresponding query
JSON shape, including `ipv4`/`ipv6` family strings. Address/Neighbor interface
names are `null` because notifications contain indices. Unknown messages
expose message type, sequence, flags and payload as a byte-number array.
Events keep arrival order. Without `--jsonl`, the CLI writes the object kind
and typed debug representation.

Kernel failures display errno and available extack text/offset on stderr.
Event loss displays a request to query a fresh snapshot and exits nonzero;
the CLI does not reconnect silently. Monitor buffering and recovery rules are
documented in [transport.md](transport.md).

## Plan and apply

```text
moonnet plan desired.json [--json] [--dangerous]
moonnet apply desired.json [--json] [--dangerous]
moonnet apply desired.json --yes [--json] [--dangerous]
```

`plan` and unconfirmed `apply` perform the same read-only planning workflow.
Only `apply --yes` enables sequential execution, compensation on failure and
fresh desired-state verification. `plan --yes` and duplicate confirmation are
rejected. A regular UTF-8 configuration file is read with a 1 MiB limit before
opening a route socket. Schema and SDK validation errors remain structured.
Planning uses a fresh snapshot and shared safety validation. Loopback/default
route changes require explicit `--dangerous`, which alone does not execute them.
Preview JSON is the version-1 Plan shape; human output lists every exact
operation, reason and danger marker. Duplicate or unknown flags fail.

Confirmed apply emits an ApplyReport (JSON or human) with completed, failed and
unexecuted steps, each compensation result and final verification. Reports go
to stdout before a nonzero exit for mutation failure, cancellation, unmet goals
or verification error. Preflight rejection reports its original error on stderr
before any write. See [reconcile.md](reconcile.md) for outcome uncertainty and
recovery limits. Run `bash .ci/validate-apply.sh` for a disposable namespace demo.
