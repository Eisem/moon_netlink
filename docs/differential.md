# `ip -j` differential baseline / `ip -j` 差分基线

`.ci/diff_ip_json.py` runs the four read-only `moonnet ... show --json`
commands beside iproute2 and compares their shared, stable fields:

`.ci/diff_ip_json.py` 同时运行四种只读 `moonnet ... show --json` 和 iproute2 命令，比较双方共同的稳定字段：

- Link: index, name, MTU, Ethernet/loopback MAC, and operational state;
   Link：索引、名称、MTU、以太网或回环 MAC，以及运行状态；
- Address: interface, family, local address, prefix length, and scope;
   Address：接口、协议族、本地地址、前缀长度、作用域；
- Route: family, destination prefix, gateway, output interface, table, and
  metric;
   Route：协议族、目的前缀、网关、输出接口、表、metric；
- Neighbor: destination, interface, link-layer address, and NUD state.
   Neighbor：目的地址、接口、链路层地址、NUD 状态。

The route and neighbor checks intentionally require every iproute2 row to be
present in MoonNetlink while allowing extra kernel records in MoonNetlink.
iproute2 filters some records when rendering these commands; retaining them is
part of the SDK's loss-minimizing behavior.

Route、Neighbor 检查要求 iproute2 的每条记录都出现在 MoonNetlink 中，同时允许 MoonNetlink 有额外内核记录。iproute2 在输出时过滤部分记录；SDK 保留它们，以尽量减少信息丢失。

Run on Linux from the repository root:

在 Linux 上从仓库根目录运行：

```sh
python3 .ci/diff_ip_json.py
```

The first baseline was recorded on 2026-10-03 under WSL2. It passed with
Link 2/2, Address 5/5, Route 12/12, and Neighbor 1 iproute2 row covered by 6
MoonNetlink records. Counts are environment-dependent; the script compares
the live values rather than pinning those counts.

首次基线记录于 2026-10-03 的 WSL2，Link 2/2、Address 5/5、Route 12/12 均通过；iproute2 的 1 条 Neighbor 记录被 MoonNetlink 的 6 条记录覆盖。数量随环境变化；脚本比较实时值，不固定这些数量。

For non-Ethernet links, iproute2's `address` can be an IP endpoint or another
hardware address; it is not the SDK's six-byte `mac`. The comparison normalizes
`mac` to `null` for those link types. The SDK retains their raw `IFLA_ADDRESS`
attribute. `.ci/validate-queries.sh` also exercises this mapping with a real
IPIP interface and compares all four object queries in an isolated namespace.

对非以太网链路，iproute2 的 `address` 可能是 IP 端点或其他硬件地址，不等同于 SDK 的六字节 `mac`。对拍将这些链路的 `mac` 规范化为 `null`，SDK 仍保留原始 `IFLA_ADDRESS`。`.ci/validate-queries.sh` 也在隔离命名空间通过真实 IPIP 接口检查此映射并比较四类对象查询。

`.ci/validate-mutations.sh` additionally compares all four queries while
SDK-configured IPv4/IPv6 addresses, routes in table 1000, MTU 1400 and permanent
IPv4/IPv6 neighbors exist. It verifies replacement and deletion with direct
`ip -j` assertions and checks the concurrent JSONL event stream. On the tested
WSL2 Linux 6.6 namespace, the shared fields agreed for 3 links, 6 addresses,
17 routes and 2 iproute2 neighbor records (9 SDK records). Counts are a record
of that topology, not fixed assertions about arbitrary hosts.

`.ci/validate-mutations.sh` 在 SDK 配置的 IPv4/IPv6 地址、table 1000 路由、MTU 1400 和永久 IPv4/IPv6 Neighbor 存在时对拍四种查询，并通过直接 `ip -j` 断言验证替换、删除及并发 JSONL 事件流。在已测试的 WSL2 Linux 6.6 命名空间，3 个链路、6 个地址、17 条路由和 2 条 iproute2 邻居记录（SDK 有 9 条）的共同字段一致。数量是该拓扑的记录，不是任意主机的固定断言。
