# `ip -j` differential baseline

`.ci/diff_ip_json.py` runs the four read-only `moonnet ... show --json`
commands beside iproute2 and compares their shared, stable fields:

- Link: index, name, MTU, Ethernet/loopback MAC, and operational state;
- Address: interface, family, local address, prefix length, and scope;
- Route: family, destination prefix, gateway, output interface, table, and
  metric;
- Neighbor: destination, interface, link-layer address, and NUD state.

The route and neighbor checks intentionally require every iproute2 row to be
present in MoonNetlink while allowing extra kernel records in MoonNetlink.
iproute2 filters some records when rendering these commands; retaining them is
part of the SDK's loss-minimizing behavior.

Run on Linux from the repository root:

```sh
python3 .ci/diff_ip_json.py
```

The first baseline was recorded on 2026-10-03 under WSL2. It passed with
Link 2/2, Address 5/5, Route 12/12, and Neighbor 1 iproute2 row covered by 6
MoonNetlink records. Counts are environment-dependent; the script compares
the live values rather than pinning those counts.

For non-Ethernet links, iproute2's `address` can be an IP endpoint or another
hardware address; it is not the SDK's six-byte `mac`. The comparison normalizes
`mac` to `null` for those link types. The SDK retains their raw `IFLA_ADDRESS`
attribute. `.ci/validate-queries.sh` also exercises this mapping with a real
IPIP interface and compares all four object queries in an isolated namespace.

`.ci/validate-mutations.sh` additionally compares all four queries while
SDK-configured IPv4/IPv6 addresses, routes in table 1000, MTU 1400 and permanent
IPv4/IPv6 neighbors exist. It verifies replacement and deletion with direct
`ip -j` assertions and checks the concurrent JSONL event stream. On the tested
WSL2 Linux 6.6 namespace, the shared fields agreed for 3 links, 6 addresses,
17 routes and 2 iproute2 neighbor records (9 SDK records). Counts are a record
of that topology, not fixed assertions about arbitrary hosts.
