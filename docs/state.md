# Declarative state model

`state` is pure and depends on `route`, with no socket or async dependency.
`NetworkSnapshot::new` copies Link/Address/Route/Neighbor collections and their
unknown-attribute collections, preserving every domain field. Immutable
payload bytes remain owned values.

Names identify desired links; indices reference objects in an observation.
`interface_name` and `link_by_name` return `None` for missing/unnamed objects.
A caller collects four dumps and constructs the snapshot. These observations
are not an atomic kernel snapshot.

`normalize` copies and sorts all collections, using link/interface name then
complete raw fields as tie-breakers. It resolves Address/Neighbor names from
the observed links, without changing the input. `to_json` always normalizes and
emits schema version 1, canonical IP text and explicit nulls. Each object also
includes raw typed Debug text containing every field and unknown attribute;
that debug text is diagnostic, not a stable schema for application parsing.
Default destinations are explicit zero addresses only for prefix zero. The
supported route subset normalizes an absent metric to IPv4 zero / IPv6 1024.

`moonnet snapshot` collects four read-only dumps and emits JSON. Volatile
fields can change between samples; byte determinism means identical input
observations give identical output, not that a live network remains static.

## Desired schema version 1

`DesiredState::parse` accepts `schema_version: 1` and optional `links`,
`addresses`, `routes` arrays (at most 1024 each). Every resource requires
`ensure: present|absent`. Link fields are `name`, optional boolean `up` and
positive u32 `mtu`; addresses require `interface`, IP `address` and numeric
`prefix_length`, with optional byte `scope` (default 0). Routes require
`interface`, canonical IP `destination`, numeric `prefix_length`; optional
`gateway` is an IP string, `table` defaults to 254, `protocol` to 4, `priority`
to IPv4 0 / IPv6 1024. IPv4 direct-route scope defaults to 253, others to 0.
Explicit IPv6 priority zero also means the kernel user-route default 1024.

Numeric fields require unsigned decimal integer literals (`0` or digits);
decimal points, exponents and minus signs are rejected before conversion.
This prevents Double rounding or underflow from silently accepting a fraction.
Quoted strings such as IP addresses are unaffected.

Unknown keys, wrong types, noninteger/out-of-range numbers, invalid names,
family/prefix mismatches and noncanonical routes fail. Repeated resource
identities are rejected, including opposite ensure intents. `validate_desired`
also checks typed SDK callers. Schema errors contain field paths; JSON syntax
and IP/route validation retain their original error types. JSON nesting and
input size are bounded. Parsing uses the core JSON parser's object-key rules.

`evaluate_intent` considers only explicitly declared resources. Present means
the declared identity and supported fields match; absent means that identity
does not exist. Missing interfaces satisfy absent Address/Route intents but
fail present intent before planning. IPv6 address matching uses IFA_ADDRESS
when IFA_LOCAL is absent; default-route destination/priority are normalized.
Unspecified resources, flags and link fields remain unmanaged.

Link creation/deletion is outside the SDK subset, so absent Link is explicitly
rejected; `up=false` requests disabling an existing link. Existing point-to-point
addresses, mismatched scope/protocol or unsupported route features fail instead
of constructing a mutation that cannot reproduce their semantics. Migration
of unsupported properties requires a future explicit API, not implicit deletion.

`diff(snapshot, desired)` returns supported typed `Change` values after complete
preflight. Link changes retain before/after values; Address/Route changes carry
exact SDK specs and resolved indices. Satisfied fields produce no change.
Unmanaged resources never generate deletions. Competing route slots or local
addresses reject exclusive adds unless the old identity is explicitly absent.
Two present route intents for one kernel slot conflict, even with different
gateways/interfaces. An explicit delete/add migration is permitted. Diff order
is deterministic but dependency ordering belongs to `Plan`; no I/O is performed.

`build_plan(snapshot, desired)` orders route deletions, address deletions, MTU
preparation, Link UP, address additions, route additions, then Link DOWN.
Full change values break ties, so input order cannot change the plan. Every
step includes a reason and a danger marker for loopback (including its kernel
flag) or default-route changes. `Plan::to_json` emits version 1 and exact
operation arguments. Generating a plan is pure and does not apply changes;
`validate_plan(plan, snapshot, dangerous=false)` checks every step before a
write. Loopback names/kernel flags and IPv4/IPv6 default-route additions or
deletions are protected. It recomputes protection even if callers edit the
display marker. Explicit dangerous permits those resources; stale/missing
interface indices and invalid SDK specs still fail. The future executor and
CLI must reuse this check. Concurrent changes after observation remain possible.
