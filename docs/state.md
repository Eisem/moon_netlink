# Declarative state model

`state` is pure and depends on `route`, with no socket or async dependency.
`NetworkSnapshot::new` copies Link/Address/Route/Neighbor collections and their
unknown-attribute collections, preserving every domain field. Immutable
payload bytes remain owned values.

Names identify desired links; indices reference objects in an observation.
`interface_name` and `link_by_name` return `None` for missing/unnamed objects.
A caller collects four dumps and constructs the snapshot. These observations
are not an atomic kernel snapshot. JSON and planning are separate tasks.

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

Unknown keys, wrong types, noninteger/out-of-range numbers, invalid names,
family/prefix mismatches and noncanonical routes fail. Repeated resource
identities are rejected, including opposite ensure intents. `validate_desired`
also checks typed SDK callers. Schema errors contain field paths; JSON syntax
and IP/route validation retain their original error types. JSON nesting and
input size are bounded. Parsing uses the core JSON parser's object-key rules.
Interpretation of present/absent and diff are the next independent tasks.
