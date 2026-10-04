# Reproducible demonstrations / 可复现演示

One entry runs every scenario and an invalid-schema refusal:

通过一个入口运行全部场景，并验证无效 schema 被拒绝：

```sh
moon update
bash demo/run.sh
```

Select `container`, `reconcile`, `monitor`, `failure` or `invalid` as its optional
argument to run one scenario. Unknown arguments exit 2. The complete run exits
zero only if successful operations, expected nonzero CLI failures, observations
and cleanup assertions all pass. Output appears as each stage completes and can
be used directly for a recorded presentation.

可选参数 `container`、`reconcile`、`monitor`、`failure`、`invalid` 用于运行单个场景；未知参数退出码为 2。只有成功操作、预期 CLI 非零失败、观测和清理断言全部通过，完整入口才以零退出。每个阶段完成后即时显示输出，可直接用于录制演示。

Run on Linux with MoonBit's native toolchain, a C compiler, Python 3 and
iproute2. The kernel must permit `unshare -Urn` (user and network namespaces).
Each wrapper checks that its network namespace differs from the caller's and
creates disposable veth interfaces. Missing tools or namespace permissions
produce a nonzero exit; no fallback changes the host network. All subprocesses
have bounded execution time. The namespace and interfaces disappear on success
or failure when its last process exits.

需要 Linux、MoonBit native 工具链、C 编译器、Python 3、iproute2，内核必须允许 `unshare -Urn` 创建用户和网络命名空间。每个包装脚本检查其网络命名空间不同于调用者，并创建可丢弃 veth。缺工具或权限会非零退出，不会回退到宿主网络执行。所有子进程均有执行时限；无论成功或失败，最后一个进程退出后命名空间及接口消失。

## Container initialization through the SDK / 使用 SDK 初始化容器网络

```sh
bash demo/container.sh
```

The MoonBit [SDK example](../examples/configure_veth/main.mbt) uses public
`RouteClient` methods to configure MTU, UP, IPv4/IPv6 addresses and nondefault
routes on a disposable veth. It also checks exclusive duplicates, replacement
and kernel extended diagnostics. The demo independently queries the actual
state, compares it with `ip -j`, then deletes configured resources through the
SDK and checks the resulting MTU/DOWN state. The namespace is released even if
initialization fails partway; this direct SDK example has no atomic rollback.

MoonBit [SDK 示例](../examples/configure_veth/main.mbt) 使用公共 `RouteClient` 方法，在临时 veth 上配置 MTU、UP、IPv4/IPv6 地址和非默认路由，也检查排他添加重复、替换和内核扩展诊断。演示独立查询实际状态，与 `ip -j` 对拍，再通过 SDK 删除资源，验证 MTU/DOWN。即使初始化中途失败，也会释放命名空间；该直接 SDK 示例没有原子回滚。

`ip` is used to create the namespace fixture and to independently validate it.
The MoonBit example sends mutations through RTNetlink, without invoking `ip`.

`ip` 用于创建命名空间测试环境及独立验证；MoonBit 示例通过 RTNetlink 发送修改，不调用 `ip`。

## Snapshot, plan and apply / 快照、规划与应用

From the repository root:

从仓库根目录运行：

```sh
moon update
bash demo/reconcile.sh
```

The script uses the fixed [desired configuration](../demo/desired.json) and the
public `moonnet` CLI. Its output follows the actual workflow:

脚本使用固定 [目标配置](../demo/desired.json) 和公共 `moonnet` CLI，输出对应以下真实流程：

1. Initial snapshot and independently observed veth configuration.
   初始快照与独立观测到的 veth 配置。
2. Six ordered operations: MTU, UP, IPv4/IPv6 addresses and nondefault routes.
   Plan and unconfirmed apply agree; the configuration remains unchanged.
   六项有序操作：MTU、UP、IPv4/IPv6 地址和非默认路由；plan 与未确认 apply 一致，配置保持不变。
3. Explicit `apply --yes`, its acknowledged operations and final verification.
   显式 `apply --yes`、已确认操作和最终验证。
4. Final snapshot and query comparison with `ip -j`.
   最终快照及与 `ip -j` 的查询对拍。
5. Empty second plan and successful second apply with zero operations.
   第二次计划为空，第二次 apply 成功且执行零项操作。
6. Namespace released.
   释放命名空间。

Assertions make any unexpected outcome fail the demo. Snapshot summaries show
object counts; full canonical snapshots are available with `moonnet snapshot`.
The query comparison uses the documented typed fields; extra kernel neighbor
entries can exist beyond the subset listed by `ip -j`. Address state and counts
can also vary during IPv6 duplicate-address detection.

任何不符合预期的结果都会使断言失败。快照摘要显示对象数量；完整规范化快照可通过 `moonnet snapshot` 获取。对拍使用文档列出的类型化字段；SDK 可包含 `ip -j` 未列出的额外内核邻居项。IPv6 重复地址检测期间，地址状态和数量也可能变化。

This workflow demonstrates supported managed fields and fresh observation.
It does not make kernel mutations atomic or reproduce every kernel metadata
field; see [reconciliation limits](reconcile.md).

该流程演示受支持的管理字段和重新观测，不使内核修改成为原子操作，也不重现每个内核元数据字段；详见 [收敛边界](reconcile.md)。

## Protection and a controlled mid-plan failure / 保护与受控中途失败

```sh
bash demo/failure.sh
```

First, a confirmed loopback change must be rejected before writing; `lo` stays
UP. The fixed [failure configuration](../demo/failure-desired.json) then changes
MTU/UP, adds two addresses and a valid route before requesting an unreachable
gateway. Linux rejects operation six with errno 101. The demo displays the
original structured error, five completed indices, one skipped operation,
reverse compensation and a fresh observation of the restored managed fields.
Final verification must still report the desired state unmet.

首先，确认后的回环修改必须在写入前被拒绝，`lo` 保持 UP。随后固定 [失败配置](../demo/failure-desired.json) 修改 MTU/UP、添加两个地址和一条有效路由，再请求不可达网关。Linux 以 errno 101 拒绝第六项操作。演示显示原始结构化错误、五项完成索引、一项跳过、倒序补偿，以及对已恢复管理字段的重新观测；最终验证仍须报告目标未达成。

Each expected CLI failure must exit nonzero. The wrapper exits zero only when
all failure and recovery assertions pass. It does not deliberately cause kernel
event loss or compensation failure; independent backend tests cover compensation
errors, while `.ci/validate-failures.sh` also restores preexisting resources.

每次预期 CLI 失败必须非零退出。只有全部失败和恢复断言通过，包装脚本才以零退出。此演示不故意造成内核事件丢失或补偿失败；独立 backend 测试覆盖补偿错误，`.ci/validate-failures.sh` 还验证恢复预先存在的资源。

## Concurrent typed monitoring and filtering / 并行类型化监听与过滤

```sh
bash demo/monitor.sh
```

Two monitors subscribe and signal ready before the CLI applies the fixed desired
state and then removes the explicitly managed addresses/routes. The demo prints
projections of real Link and IPv4/IPv6 Address/Route events. It requires both
additions and deletions and verifies that the route-only subscription receives
only route events. Every listener and pipe reader is stopped in `finally`, even
when an assertion or command fails.

两个监听器先订阅并报告 ready，再由 CLI 应用固定目标状态，随后移除显式管理的地址、路由。演示显示真实 Link、IPv4/IPv6 Address/Route 事件的字段摘要，要求收到添加和删除，并验证 route-only 订阅只收到路由事件。即使断言或命令失败，所有监听进程和管道读取线程也会在 `finally` 停止。

Netlink multicast is lossy. The CLI exits with a diagnostic on
`EventStreamLost`; consumers must discard their cached state, query a fresh
snapshot and resubscribe. The demo explains this recovery but does not force
kernel event loss. The deterministic overrun fixture is checked separately:

Netlink 组播可能丢失事件。出现 `EventStreamLost` 时 CLI 显示诊断并退出；使用方应丢弃缓存状态，重新查询快照并重新订阅。演示解释该恢复流程，但不强制触发内核丢事件。确定性的 overrun 样例单独检查：

```sh
moon test transport --target native --filter '*overrun*'
```
