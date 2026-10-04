# MoonNetlink

Descriptions below pair English with Chinese; commands and API names are shared.

下文采用英文、中文对照说明；命令示例和 API 名称共用一份。

MoonNetlink is a typed RTNetlink SDK and declarative Linux network state
toolkit for MoonBit.

MoonNetlink 是面向 MoonBit 的类型化 RTNetlink SDK 与声明式 Linux 网络状态工具。

The SDK currently supports typed Link/Address/Route/Neighbor queries,
Link UP/DOWN and MTU changes, IPv4/IPv6 address and unicast route add/delete,
and typed multicast events. Protocol encoding and decoding are implemented
in MoonBit; the C shim only opens and transfers the Linux socket. SDK queries
and mutations do not invoke `ip`. The state package provides owned snapshots,
strict desired configuration parsing, scoped differences and deterministic
plans. The planning CLI defaults to dry-run and checks critical-resource
protections. Explicit `apply --yes` executes in order, reports partial failure,
attempts compensation and verifies desired state with a fresh observation.

SDK 目前支持类型化的 Link（链路）、Address（地址）、Route（路由）、Neighbor（邻居表）查询，链路 UP/DOWN 与 MTU 修改，IPv4/IPv6 地址和单播路由的添加、删除，以及类型化组播事件。协议编解码由 MoonBit 实现；C shim 只负责打开 Linux socket 并移交其所有权。SDK 查询和修改不调用 `ip`。state 包提供拥有数据所有权的快照、严格的目标配置解析、限定管理范围的差分和确定性计划。规划 CLI 默认为 dry-run（预演），并检查关键资源保护。显式执行 `apply --yes` 时按顺序修改，报告部分失败，尝试补偿，再重新查询以验证目标状态。

Source files to commit and local files to exclude are listed in
[docs/repository.md](./docs/repository.md).

需要提交的源码与应排除的本地文件见 [提交边界说明](./docs/repository.md)。

The implementation layers and their validation evidence are explained in
[docs/architecture.md](./docs/architecture.md).

各实现层的职责与验证证据见 [架构说明](./docs/architecture.md)。

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
Ordered execution and partial-failure reports are documented in
[docs/reconcile.md](./docs/reconcile.md).
Fixed-seed malformed-input checks and their execution budget are documented in
[docs/robustness.md](./docs/robustness.md).

原生文件描述符所有权和可疑截断时拒绝结果的策略见 [传输层说明](./docs/transport.md)。独立于传输层的消息、属性、控制消息规则见 [核心协议说明](./docs/core.md)。类型化模型覆盖范围与校验规则见 [模型说明](./docs/route.md)。查询、事件 CLI 与确定性 JSON 约定见 [CLI 说明](./docs/cli.md)。Linux 下与 `ip -j` 的可复现对拍见 [差分验证说明](./docs/differential.md)。目标配置 schema、快照与纯规划 API 见 [状态模型说明](./docs/state.md)。顺序执行和部分失败报告见 [收敛执行说明](./docs/reconcile.md)。固定 seed 畸形输入检查与运行预算见 [健壮性说明](./docs/robustness.md)。

## CLI / 命令行

Build and test from a checkout with the MoonBit toolchain and a C compiler:

安装 MoonBit 工具链和 C 编译器后，从源码检出目录构建、测试：

```sh
git clone https://github.com/Eisem/moon_netlink.git
cd moon_netlink
moon update
moon check --target native
moon test --target native
```

Run the following commands on Linux:

在 Linux 上运行以下命令：

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

All four query commands sort their output deterministically. JSON uses canonical
address text, ordinary numbers for present values, and `null` for absent ones.

四种对象查询均按确定性顺序输出。JSON 使用规范化地址文本，数值字段有值时输出普通数字，缺失时输出 `null`。

## SDK query examples / SDK 查询示例

On Linux with MoonBit and a C compiler:

在安装了 MoonBit 和 C 编译器的 Linux 环境中运行：

```sh
moon run --target native examples/inspect_links
moon run --target native examples/inspect_addresses
moon run --target native examples/inspect_routes
moon run --target native examples/inspect_neighbors
```

Expected output contains a line for the loopback interface named `lo`, at least
one typed address from `RTM_GETADDR`, typed routes from `RTM_GETROUTE`, and a
successful `RTM_GETNEIGH` dump (which may contain zero entries on an idle host).

预期输出包含名为 `lo` 的回环接口、来自 `RTM_GETADDR` 的至少一个类型化地址、来自 `RTM_GETROUTE` 的类型化路由，以及成功完成的 `RTM_GETNEIGH` 导出；空闲主机的邻居表可能为空。

## Platform / 平台要求

MoonNetlink targets Linux on MoonBit's native backend. Queries and monitoring
normally run without root; mutations require network administration privileges
in the process's network namespace. Pure codec tests also run on Windows;
opening a Linux route socket there returns `UnsupportedPlatform`.

MoonNetlink 面向 MoonBit native 后端上的 Linux。查询和监听通常不需要 root；修改需要调用进程所在网络命名空间内的网络管理权限。纯编解码测试也可在 Windows 运行，但在那里打开 Linux route socket 会返回 `UnsupportedPlatform`。

## Isolated mutation and monitor example / 隔离修改与监听示例

On Linux with MoonBit, a C compiler, Python 3, iproute2, and permitted user/network
namespaces:

需要 Linux、MoonBit、C 编译器、Python 3、iproute2，以及允许创建用户和网络命名空间的环境：

```sh
bash .ci/validate-mutations.sh
```

This creates a disposable veth pair inside `unshare -Urn`, runs
`examples/configure_veth` to configure MTU, UP state, IPv4/IPv6 addresses and
routes, verifies exclusive/replace behavior and kernel diagnostics, compares
with `ip -j`, and removes the configuration. Concurrent `watch --jsonl` streams
verify Link, Address, Route and Neighbor events. The namespace and processes
are cleaned up on success or failure. No host interface is modified.

脚本在 `unshare -Urn` 内创建临时 veth 对，运行 `examples/configure_veth` 配置 MTU、UP、IPv4/IPv6 地址和路由，验证排他添加、替换行为和内核诊断，与 `ip -j` 对拍后删除配置。并行的 `watch --jsonl` 流验证 Link、Address、Route、Neighbor 事件。无论成功或失败，都会清理命名空间和进程，不修改宿主接口。

The example requires an explicit `--yes`; use it only on a disposable interface
inside a temporary namespace. The SDK applies mutations directly. Default
dry-run and loopback/default-route checks are available in the planning CLI;
confirmed `apply --yes` uses the same checks and reports final verification.
Direct SDK mutations remain the caller's responsibility. Use
`bash .ci/validate-apply.sh` to demonstrate confirmed apply in a temporary
namespace. Recovery is best-effort and does not provide atomic transactions.

示例要求显式传入 `--yes`，仅应在临时命名空间内的可丢弃接口上运行。SDK 直接执行修改；规划 CLI 提供默认预演和回环接口、默认路由保护，确认后的 `apply --yes` 复用这些检查并报告最终验证结果。直接使用 SDK 修改时由调用者负责保护。可通过 `bash .ci/validate-apply.sh` 在临时命名空间演示确认执行。恢复属于尽力补偿，不提供原子事务。

## Run isolated demonstrations / 运行隔离演示

```sh
bash demo/run.sh
```

This entry demonstrates SDK container initialization, snapshot/plan/apply,
typed monitoring, protected refusal and actual failure recovery. It verifies
fresh observations, `ip -j` comparison and an empty second plan using fixed
desired files. See [prerequisites, commands and expected output](docs/demo.md).

该入口演示 SDK 容器网络初始化、snapshot/plan/apply、类型化监听、受保护操作拒绝和真实失败恢复；使用固定目标文件验证重新观测、`ip -j` 对拍和第二次空计划。详见 [依赖、命令与预期输出](docs/demo.md)。

## License / 许可证

MIT

MIT 许可证。
