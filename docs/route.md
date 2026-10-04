# Typed route models

The `route` package translates RTNetlink family payloads into owned public
models. The generic wire framing remains in `core`; socket lifecycle and
multipart collection remain in `transport`.

## Link

`decode_link` currently models the following `RTM_NEWLINK` data:

- interface index and flags from `ifinfomsg`;
- `IFLA_IFNAME`;
- nested `IFLA_LINKINFO/IFLA_INFO_KIND`;
- `IFLA_MTU`;
- six-byte `IFLA_ADDRESS` as `MacAddress` for Ethernet and loopback;
- `IFLA_OPERSTATE` as `LinkOperationalState`;
- `IFLA_MASTER`;
- all attributes not otherwise modeled.

Netlink strings must contain exactly one terminating NUL and valid UTF-8.
Fixed-width integer, state, and MAC attributes must have their exact kernel ABI
length. Violations return `CodecError::InvalidString` or
`CodecError::UnexpectedFieldLength`; malformed kernel data is never silently
truncated or decoded lossily.

`ifinfomsg.ifi_type` distinguishes Ethernet/loopback from other link types.
IPIP, InfiniBand and other hardware addresses are preserved as raw
`IFLA_ADDRESS` entries in `unknown_attributes`, with `mac = None`. Their
different or empty address lengths do not invalidate the entire Link dump.
Ethernet and loopback MAC lengths are still checked strictly.

`MacAddress` can return its immutable bytes, parse exactly six colon-separated
two-digit hexadecimal octets, and format canonical lower-case colon notation.

Query constructors cover an all-link dump and point queries by positive index
or interface name. Name queries enforce Linux's 15-byte UTF-8 limit, reject
embedded NUL code units, and validate UTF-16 before calling the UTF-8 encoder.
`encode_set_link_state` builds an acknowledged `RTM_NEWLINK` mutation whose
`ifi_change` mask contains only `IFF_UP`, preserving every unrelated flag.
`RouteClient::get_link_by_index` and `get_link_by_name` execute these point
queries with the same mutex and timeout as dumps, returning one typed `Link`.

## Address

`encode_get_addresses` builds an all-family `RTM_GETADDR` dump. `decode_address`
validates `ifaddrmsg`, IPv4/IPv6 byte widths, labels, extended flags, and
unknown attributes. `IpAddress` wraps fixed-width `Ipv4Address` and
`Ipv6Address` values so invalid byte lengths cannot be constructed through the
public API. The kernel message contains only an interface index;
`Address.interface_name` is resolved by `RouteClient` dump methods using Link
data. Raw decoders and monitor events retain `None`. IPv6 commonly carries
only `IFA_ADDRESS`, so `local_address` can be absent even for a local address.

## Route

`encode_get_routes` builds an all-family, all-table `RTM_GETROUTE` dump.
`decode_route` models destination/source prefixes, gateway, preferred source,
input/output interface indices, table, priority, protocol, scope, route type,
TOS, flags, and unknown attributes. A 32-bit `RTA_TABLE` overrides the legacy
8-bit table field. IP attributes reuse the strict family-specific width checks
from Address decoding. Routes expose interface indices.

## Neighbor

`encode_get_neighbors` builds an all-family `RTM_GETNEIGH` dump.
`decode_neighbor` validates the 12-byte `ndmsg`, family-specific destination
width, six-byte link-layer address, and 32-bit probe count. It exposes the
interface index, typed NUD state, flags, neighbor type, and preserves unknown
attributes. `RouteClient` resolves `interface_name` for dumps; raw decoders and
monitor events leave it absent.

## Text addresses

`Ipv4Address::parse`, `Ipv6Address::parse`, `IpAddress::parse`, and
`MacAddress::parse` provide strict owned values whose byte widths cannot be
invalid. IPv4 requires four decimal components and rejects leading zeroes.
IPv6 accepts one optional `::` and an optional final dotted-decimal IPv4 tail,
then formats in lower-case RFC 5952 style with the first longest zero run
compressed. MAC input requires six two-digit hexadecimal octets. Parse errors
retain the original input in the public `AddressParseError` variants.

## Wire fixtures

Black-box tests cover every Phase 2 object from complete Netlink datagrams.
`link_fixture_test.mbt` contains a real Linux loopback multipart capture plus
its `NLMSG_DONE`; `object_fixture_test.mbt` contains deterministic,
de-identified Linux-UAPI fixtures for Address, Route, and Neighbor. The latter
use documentation-only `192.0.2.0/24` values and verify both typed fields and
lossless message framing round-trips.

## Mutation subset

`encode_set_link_mtu` changes only `IFLA_MTU`, with a zero `ifi_change` mask.
The UP/DOWN constructor changes only `IFF_UP`. Both preserve unrelated flags.

`AddressSpec` describes one local IPv4/IPv6 address: interface index, address,
prefix length and scope. Add/delete encode matching `IFA_LOCAL` and
`IFA_ADDRESS`; peer addresses, lifetimes and address-label configuration are
outside this subset. The prefix is checked against the address family.

`RouteSpec` describes a canonical unicast destination, optional gateway,
positive output interface, numeric nonzero table, optional priority, protocol
and scope. Host bits in the destination must be zero and the gateway must
match its family. `::/0` and `0.0.0.0/0` express default routes. Tables above
255 are encoded through `RTA_TABLE`. Multipath, rules, source-specific routes,
onlink flags and other route types are outside this mutation API.

Add methods default to `AddMode::Exclusive` (`REQUEST|ACK|CREATE|EXCL`, 0x0605).
`AddMode::Replace` explicitly requests create-or-replace
(`REQUEST|ACK|CREATE|REPLACE`, 0x0505). Linux decides which existing object
matches the request; a replacement does not remove every object with the same
destination. Delete methods use `REQUEST|ACK` (0x0005) and include the supplied
identifying fields. The SDK never retries mutations automatically.

`RouteClient` exposes `set_link_mtu`, `add_address`, `delete_address`,
`add_route` and `delete_route` under its existing mutex and timeout. Success
means the kernel acknowledged the request; query again to verify actual state.
These SDK methods require Linux network administration privileges and act in
the calling process's network namespace. They do not provide the planned
declarative engine's dry-run or critical-resource guards.

## Events

`RouteEvent` decodes RTM_NEW/DEL Link, Address, Route and Neighbor messages.
`LinkChanged` and `NeighborChanged` include both creation and updates because
the wire message does not identify them separately. All modeled fields and
unknown attributes are retained. Other family message types produce
`Unknown(NetlinkMessage)`; generic controls belong to `transport`.

Protocol layout and flag semantics follow the Linux UAPI and the official
[Netlink introduction](https://docs.kernel.org/userspace-api/netlink/intro.html)
and [route family specification](https://kernel.org/doc/html/v6.16/networking/netlink_spec/rt-route.html).
