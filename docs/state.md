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
