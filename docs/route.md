# Typed route models / 类型化路由模型

The `route` package translates RTNetlink family payloads into owned public
models. The generic wire framing remains in `core`; socket lifecycle and
multipart collection remain in `transport`.

`route` 包将 RTNetlink 协议族载荷转换为拥有数据所有权的公共模型。通用二进制封装由 `core` 负责；socket 生命周期和多部分响应收集由 `transport` 负责。

## Link / 链路

`decode_link` currently models the following `RTM_NEWLINK` data:

`decode_link` 目前建模以下 `RTM_NEWLINK` 数据：

- interface index and flags from `ifinfomsg`;
   `ifinfomsg` 中的接口索引与标志；
- `IFLA_IFNAME`;
   接口名称 `IFLA_IFNAME`；
- nested `IFLA_LINKINFO/IFLA_INFO_KIND`;
   嵌套链路类型 `IFLA_LINKINFO/IFLA_INFO_KIND`；
- `IFLA_MTU`;
   MTU `IFLA_MTU`；
- six-byte `IFLA_ADDRESS` as `MacAddress` for Ethernet and loopback;
   以太网与回环接口的六字节 `IFLA_ADDRESS`，表示为 `MacAddress`；
- `IFLA_OPERSTATE` as `LinkOperationalState`;
   `IFLA_OPERSTATE`，表示为 `LinkOperationalState`；
- `IFLA_MASTER`;
   主接口索引 `IFLA_MASTER`；
- all attributes not otherwise modeled.
   所有尚未单独建模的属性。

Netlink strings must contain exactly one terminating NUL and valid UTF-8.
Fixed-width integer, state, and MAC attributes must have their exact kernel ABI
length. Violations return `CodecError::InvalidString` or
`CodecError::UnexpectedFieldLength`; malformed kernel data is never silently
truncated or decoded lossily.

Netlink 字符串必须是有效 UTF-8，且恰好包含一个末尾 NUL。定长整数、状态和 MAC 属性必须严格符合内核 ABI 的字节长度，否则返回 `CodecError::InvalidString` 或 `CodecError::UnexpectedFieldLength`。畸形内核数据不会被静默截断或有损解码。

`ifinfomsg.ifi_type` distinguishes Ethernet/loopback from other link types.
IPIP, InfiniBand and other hardware addresses are preserved as raw
`IFLA_ADDRESS` entries in `unknown_attributes`, with `mac = None`. Their
different or empty address lengths do not invalidate the entire Link dump.
Ethernet and loopback MAC lengths are still checked strictly.

`ifinfomsg.ifi_type` 区分以太网、回环接口与其他链路类型。IPIP、InfiniBand 等硬件地址以原始 `IFLA_ADDRESS` 条目保留在 `unknown_attributes` 中，`mac = None`。这些地址长度不同或为空时，不会使整个 Link 导出失败；以太网和回环接口的 MAC 长度仍严格检查。

`MacAddress` can return its immutable bytes, parse exactly six colon-separated
two-digit hexadecimal octets, and format canonical lower-case colon notation.

`MacAddress` 可返回不可变字节，严格解析六个用冒号分隔的两位十六进制字节，并输出规范化的小写冒号格式。

Query constructors cover an all-link dump and point queries by positive index
or interface name. Name queries enforce Linux's 15-byte UTF-8 limit, reject
embedded NUL code units, and validate UTF-16 before calling the UTF-8 encoder.
`encode_set_link_state` builds an acknowledged `RTM_NEWLINK` mutation whose
`ifi_change` mask contains only `IFF_UP`, preserving every unrelated flag.
`RouteClient::get_link_by_index` and `get_link_by_name` execute these point
queries with the same mutex and timeout as dumps, returning one typed `Link`.

查询构造器支持全链路导出，以及按正值索引或接口名称进行单对象查询。名称查询遵循 Linux 的 15 字节 UTF-8 上限，拒绝内嵌 NUL 码元，并在调用 UTF-8 编码器前校验 UTF-16。`encode_set_link_state` 构造需要 ACK 的 `RTM_NEWLINK` 修改，`ifi_change` 只包含 `IFF_UP`，保留其他标志。`RouteClient::get_link_by_index` 和 `get_link_by_name` 使用与导出相同的互斥锁和超时策略执行这些查询，返回一个类型化 `Link`。

## Address / 地址

`encode_get_addresses` builds an all-family `RTM_GETADDR` dump. `decode_address`
validates `ifaddrmsg`, IPv4/IPv6 byte widths, labels, extended flags, and
unknown attributes. `IpAddress` wraps fixed-width `Ipv4Address` and
`Ipv6Address` values so invalid byte lengths cannot be constructed through the
public API. The kernel message contains only an interface index;
`Address.interface_name` is resolved by `RouteClient` dump methods using Link
data. Raw decoders and monitor events retain `None`. IPv6 commonly carries
only `IFA_ADDRESS`, so `local_address` can be absent even for a local address.

`encode_get_addresses` 构造覆盖所有协议族的 `RTM_GETADDR` 导出；`decode_address` 校验 `ifaddrmsg`、IPv4/IPv6 字节宽度、标签、扩展标志和未知属性。`IpAddress` 包装定长 `Ipv4Address`、`Ipv6Address`，公共 API 无法构造错误字节长度的地址。内核消息只包含接口索引；`RouteClient` 的导出方法利用 Link 数据解析 `Address.interface_name`，原始解码器和监听事件保留 `None`。IPv6 通常只有 `IFA_ADDRESS`，因此即使是本地地址，`local_address` 也可能缺失。

## Route / 路由

`encode_get_routes` builds an all-family, all-table `RTM_GETROUTE` dump.
`decode_route` models destination/source prefixes, gateway, preferred source,
input/output interface indices, table, priority, protocol, scope, route type,
TOS, flags, and unknown attributes. A 32-bit `RTA_TABLE` overrides the legacy
8-bit table field. IP attributes reuse the strict family-specific width checks
from Address decoding. Routes expose interface indices.

`encode_get_routes` 构造覆盖所有协议族和路由表的 `RTM_GETROUTE` 导出。`decode_route` 建模目的、源前缀、网关、首选源地址、输入与输出接口索引、表、优先级、协议、作用域、路由类型、TOS、标志及未知属性。32 位 `RTA_TABLE` 覆盖旧式 8 位表字段。IP 属性复用 Address 解码中的协议族宽度校验；路由模型提供接口索引。

## Neighbor / 邻居表

`encode_get_neighbors` builds an all-family `RTM_GETNEIGH` dump.
`decode_neighbor` validates the 12-byte `ndmsg`, family-specific destination
width, six-byte link-layer address, and 32-bit probe count. It exposes the
interface index, typed NUD state, flags, neighbor type, and preserves unknown
attributes. `RouteClient` resolves `interface_name` for dumps; raw decoders and
monitor events leave it absent.

`encode_get_neighbors` 构造覆盖所有协议族的 `RTM_GETNEIGH` 导出。`decode_neighbor` 校验 12 字节 `ndmsg`、协议族对应的目的地址宽度、六字节链路层地址和 32 位探测次数，并提供接口索引、类型化 NUD 状态、标志、邻居类型，保留未知属性。`RouteClient` 为导出结果解析 `interface_name`；原始解码器和监听事件不填充该字段。

## Text addresses / 文本地址

`Ipv4Address::parse`, `Ipv6Address::parse`, `IpAddress::parse`, and
`MacAddress::parse` provide strict owned values whose byte widths cannot be
invalid. IPv4 requires four decimal components and rejects leading zeroes.
IPv6 accepts one optional `::` and an optional final dotted-decimal IPv4 tail,
then formats in lower-case RFC 5952 style with the first longest zero run
compressed. MAC input requires six two-digit hexadecimal octets. Parse errors
retain the original input in the public `AddressParseError` variants.

`Ipv4Address::parse`、`Ipv6Address::parse`、`IpAddress::parse` 和 `MacAddress::parse` 提供严格的拥有数据所有权的地址值，字节宽度始终有效。IPv4 要求四个十进制分量，拒绝前导零；IPv6 允许最多一个 `::` 及可选的末尾点分十进制 IPv4，输出按 RFC 5952 使用小写并压缩最先出现的最长连续零段。MAC 要求六个两位十六进制字节。公共 `AddressParseError` 变体保留原始输入。

## Wire fixtures / 二进制协议样例

Black-box tests cover every Phase 2 object from complete Netlink datagrams.
`link_fixture_test.mbt` contains a real Linux loopback multipart capture plus
its `NLMSG_DONE`; `object_fixture_test.mbt` contains deterministic,
de-identified Linux-UAPI fixtures for Address, Route, and Neighbor. The latter
use documentation-only `192.0.2.0/24` values and verify both typed fields and
lossless message framing round-trips.

黑盒测试从完整 Netlink 数据报覆盖 Phase 2 的每类对象。`link_fixture_test.mbt` 包含真实 Linux 回环接口的多部分抓取及 `NLMSG_DONE`；`object_fixture_test.mbt` 包含 Address、Route、Neighbor 的确定性、去标识化 Linux UAPI 样例，使用仅供文档示例的 `192.0.2.0/24` 地址，验证类型化字段及消息封装的无损往返。

## Mutation subset / 修改能力子集

`encode_set_link_mtu` changes only `IFLA_MTU`, with a zero `ifi_change` mask.
The UP/DOWN constructor changes only `IFF_UP`. Both preserve unrelated flags.

`encode_set_link_mtu` 只修改 `IFLA_MTU`，`ifi_change` 掩码为零；UP/DOWN 构造器只修改 `IFF_UP`。二者均保留无关标志。

`AddressSpec` describes one local IPv4/IPv6 address: interface index, address,
prefix length and scope. Add/delete encode matching `IFA_LOCAL` and
`IFA_ADDRESS`; peer addresses, lifetimes and address-label configuration are
outside this subset. The prefix is checked against the address family.

`AddressSpec` 描述一个本地 IPv4/IPv6 地址，包括接口索引、地址、前缀长度和作用域。添加、删除会编码匹配的 `IFA_LOCAL` 与 `IFA_ADDRESS`；对端地址、生命周期和地址标签配置不在此子集内。前缀按地址协议族校验。

`RouteSpec` describes a canonical unicast destination, optional gateway,
positive output interface, numeric nonzero table, optional priority, protocol
and scope. Host bits in the destination must be zero and the gateway must
match its family. `::/0` and `0.0.0.0/0` express default routes. Tables above
255 are encoded through `RTA_TABLE`. Multipath, rules, source-specific routes,
onlink flags and other route types are outside this mutation API.

`RouteSpec` 描述规范化的单播目的地址、可选网关、正值输出接口、非零数字路由表、可选优先级、协议及作用域。目的地址的主机位必须为零，网关协议族必须一致。`::/0` 和 `0.0.0.0/0` 表示默认路由；表号大于 255 时通过 `RTA_TABLE` 编码。多路径、规则、源特定路由、onlink 标志及其他路由类型不在此修改 API 内。

Add methods default to `AddMode::Exclusive` (`REQUEST|ACK|CREATE|EXCL`, 0x0605).
`AddMode::Replace` explicitly requests create-or-replace
(`REQUEST|ACK|CREATE|REPLACE`, 0x0505). Linux decides which existing object
matches the request; a replacement does not remove every object with the same
destination. Delete methods use `REQUEST|ACK` (0x0005) and include the supplied
identifying fields. The SDK never retries mutations automatically.

添加默认使用 `AddMode::Exclusive`（`REQUEST|ACK|CREATE|EXCL`，0x0605）；`AddMode::Replace` 显式请求创建或替换（`REQUEST|ACK|CREATE|REPLACE`，0x0505）。Linux 决定请求匹配哪个已有对象；替换不会删除所有相同目的地址的对象。删除使用 `REQUEST|ACK`（0x0005），包含调用者提供的身份字段。SDK 不会自动重试修改。

`RouteClient` exposes `set_link_mtu`, `add_address`, `delete_address`,
`add_route` and `delete_route` under its existing mutex and timeout. Success
means the kernel acknowledged the request; query again to verify actual state.
These SDK methods require Linux network administration privileges and act in
the calling process's network namespace. They do not provide the
declarative engine's dry-run or critical-resource guards.

`RouteClient` 的 `set_link_mtu`、`add_address`、`delete_address`、`add_route`、`delete_route` 使用既有互斥锁和超时策略。成功表示内核确认了请求，仍需重新查询验证实际状态。这些方法需要 Linux 网络管理权限，作用于调用进程的网络命名空间，不提供声明式引擎的预演和关键资源保护。

## Events / 事件

`RouteEvent` decodes RTM_NEW/DEL Link, Address, Route and Neighbor messages.
`LinkChanged` and `NeighborChanged` include both creation and updates because
the wire message does not identify them separately. All modeled fields and
unknown attributes are retained. Other family message types produce
`Unknown(NetlinkMessage)`; generic controls belong to `transport`.

`RouteEvent` 解码 RTM_NEW/DEL 的 Link、Address、Route、Neighbor 消息。`LinkChanged` 和 `NeighborChanged` 同时涵盖创建与更新，因为二进制消息不能单独区分它们。所有建模字段和未知属性均被保留。其他协议族消息类型返回 `Unknown(NetlinkMessage)`；通用控制消息由 `transport` 处理。

Protocol layout and flag semantics follow the Linux UAPI and the official
[Netlink introduction](https://docs.kernel.org/userspace-api/netlink/intro.html)
and [route family specification](https://kernel.org/doc/html/v6.16/networking/netlink_spec/rt-route.html).

协议布局与标志语义遵循 Linux UAPI，以及官方 [Netlink 入门文档](https://docs.kernel.org/userspace-api/netlink/intro.html) 和 [route 协议族规范](https://kernel.org/doc/html/v6.16/networking/netlink_spec/rt-route.html)。
