# Comparison contract with a script baseline / 与脚本基线的对照契约

This document fixes the shared scenario, supported input subset, compared fields
and acceptance for MoonNetlink and a plain Bash/iproute2 baseline. It is defined
before either side exists so that neither implementation can adjust the standard
to fit its own result. The machine-readable source is
[`demo/compare/contract.json`](../demo/compare/contract.json); this page explains
it and lists the evidence.

本文确定 MoonNetlink 与纯 Bash/iproute2 基线共用的场景、受支持输入范围、比较字段
和验收标准。契约先于任何一方实现而定，避免任何一方按自己的结果调整标准。机器可读
来源是 [`demo/compare/contract.json`](../demo/compare/contract.json)；本页解释它并
列出证据。

Both approaches can reach the same kernel state. The comparison therefore does
not claim that one of them is the only possible solution; it measures what each
side must implement and declare to reach the same observable result under the
same acceptance rules.

两种方式都能达到相同的内核状态。因此比较并不主张其中一方是唯一可行方案；它衡量的是
在同一验收规则下达到同样可观测结果时，各方需要实现和声明的内容。

## Shared scenario / 共同场景

Every case runs in its own disposable `unshare -Urn` user and network namespace.
The shared facility creates `lo`, a veth pair `cmpveth`/`cmppeer` and the case's
initial state before either implementation starts. `cmpveth` is the managed
interface, `cmppeer` stays unmanaged, and table `1000` is the managed routing
table. Neither side creates, renames or deletes interfaces.

每个用例都在独立的临时 `unshare -Urn` 用户/网络命名空间中运行。共享设施在任一实现
开始前创建 `lo`、veth 对 `cmpveth`/`cmppeer` 以及该用例的初始状态。`cmpveth` 是受管理
接口，`cmppeer` 不受管理，表 `1000` 是受管理路由表。双方都不创建、重命名或删除接口。

Seed commands and per-case fixture commands are recorded verbatim in the contract
and in each case file, so the initial state is reproducible rather than implicit.

种子命令和每个用例的预置命令在契约与用例文件中逐条记录，初始状态可复现而非隐含。

## Supported input subset / 受支持的输入范围

Both sides accept the same versioned JSON configuration.

双方接受同一份带版本的 JSON 配置。

| Item / 项目 | Rule / 规则 |
| --- | --- |
| Root keys / 根字段 | `schema_version` (must be 1), `links`, `addresses`, `routes` |
| Link keys / 链路字段 | `name`, `ensure`, `up`, `mtu` |
| Address keys / 地址字段 | `interface`, `ensure`, `address`, `prefix_length`, `scope` |
| Route keys / 路由字段 | `interface`, `ensure`, `destination`, `prefix_length`, `gateway`, `table`, `priority`, `protocol`, `scope` |
| Numbers / 数值 | unsigned decimal integer literals only; no sign, fraction or exponent / 只接受无符号十进制整数字面量，不允许符号、小数或指数 |
| Defaults / 默认值 | `address.scope=0`, `route.table=254`, `route.protocol=4`, IPv6 route priority `0` becomes `1024`, IPv4 route without gateway uses scope `253` |
| Size / 大小 | at most 1 MiB, at most 64 nesting levels, at most 1024 resources per collection / 最多 1 MiB、64 层嵌套、每个集合 1024 个资源 |
| Managed scope / 管理范围 | only explicitly declared resources; undeclared resources are never deleted / 只处理显式声明的资源，绝不删除未声明资源 |

Anything outside this subset is rejected **before the first mutation request**:
unknown or missing keys, wrong types, out-of-range or non-integer numbers,
invalid interface names, invalid IP/prefix/gateway combinations, duplicate
identities, conflicting intent, unsupported current resources, absent Link
intent, and protected loopback or default-route changes without `--dangerous`.
Parse-time rejections open no route socket.

超出此子集的输入在**第一笔修改请求之前**被拒绝：未知或缺失字段、类型错误、超范围或非
整数数值、非法接口名、非法 IP/前缀/网关组合、重复身份、冲突意图、不支持的当前资源、
absent Link 意图，以及在未传入 `--dangerous` 时修改受保护的回环或默认路由。解析阶段
拒绝不会打开路由 socket。

## Compared fields / 参与比较的字段

| Field / 字段 | Independent observation / 独立观测 | Why it is comparable / 可比较原因 |
| --- | --- | --- |
| Link MTU / 链路 MTU | `ip -j link show dev cmpveth` → `mtu` | Declared intent and a stable kernel attribute / 显式意图且为稳定内核属性 |
| Link administrative UP / 链路管理 UP | `ip -j link show dev cmpveth` → `flags` contains `UP` | Declared intent, independent of carrier / 显式意图，与载波无关 |
| Addresses / 地址 | `ip -j address show dev cmpveth` → `family`, `local`, `prefixlen` | Interface, family, local address, prefix and scope are declared / 接口、协议族、地址、前缀和作用域均为声明字段 |
| Managed routes / 受管理路由 | `ip -j -4/-6 route show table 1000` → `dst`, `gateway`, `metric`, `table` | Only table `1000` records are compared / 只比较表 `1000` 的记录 |
| Ordered plan / 有序计划 | operation sequence and length | The same observation and target must produce one deterministic plan / 同一观测与目标必须产生唯一确定计划 |
| Execution report / 执行报告 | exit status, completed/failed/not-executed indices, compensation indices, final verification | The caller must be able to judge the result, not just read the final state / 调用方必须能判断结果，而不只是看最终状态 |
| Kernel write attempts / 内核写入次数 | number of mutation requests actually attempted | A repeated run's "wrote nothing" claim cannot be proven by the final state alone / 重复执行“未写入”的主张无法仅由最终状态证明 |
| Pre-existing and unmanaged resources / 预置与未管理资源 | the same `ip -j` commands before and after the run | Both sides must leave them untouched / 双方都必须保持其不变 |

`ip -j route` omits the `table` field for the main table (`254`), so an observer
must treat a missing field as main rather than as an unknown table. Neighbouring
details that only one side reports, such as extra kernel records, must be
explained instead of silently ignored.

`ip -j route` 对主表（`254`）会省略 `table` 字段，因此观测方必须把缺失字段视为主表，
而不是未知表。只有一方报告的相邻细节（例如额外的内核记录）必须给出解释，而不是静默忽略。

## Excluded fields / 不参与比较的字段

| Field / 字段 | Reason / 原因 |
| --- | --- |
| Interface index / 接口索引 | Allocated by the kernel per namespace and reused after deletion / 内核按命名空间分配，删除后会被复用 |
| MAC and other hardware addresses / MAC 等硬件地址 | Random for veth unless the fixture pins them; not configured by either side / veth 默认随机，除非测试固定；双方都不配置 |
| `operstate`, carrier, `LOWER_UP` / 运行状态与派生标志 | Depend on the peer endpoint and timing / 取决于对端与时序 |
| Interface counters / 接口统计计数 | Change with unrelated traffic and time / 随无关流量和时间变化 |
| IPv6 link-local addresses and kernel host routes / IPv6 链路本地地址与内核主机路由 | Generated automatically by the kernel / 由内核自动生成 |
| Address lifetimes and DAD state (`valid_lft`, `preferred_lft`, `tentative`) | Time-dependent; duplicate-address detection is asynchronous / 与时间相关，重复地址检测是异步的 |
| Kernel connected routes in the main table / 主表中的内核直连路由 | A side effect of adding an address, not a declared resource / 添加地址的副作用，不是声明资源 |
| Route `linkdown` and other peer-derived flags / 路由 `linkdown` 等对端派生标志 | Bringing one veth endpoint up or down changes the peer's carrier while the configured route is unchanged / 改变 veth 一端状态会改变对端载波，而配置的路由并未变化 |
| Neighbour entries / 邻居表项 | Populated by kernel traffic and reachability probes / 由内核流量与可达性探测填充 |
| Kernel object return order / 内核返回对象顺序 | Both sides must normalize and sort before comparing / 双方都必须先规范化并排序 |
| Wall-clock duration / 实际耗时 | Belongs to the separate performance baseline, not to this acceptance contract / 属于独立性能基线，不属于本验收契约 |

## Cases and acceptance / 用例与验收

Each case declares its initial state, target, expected operations, expected exit
status and the result that must remain independently queryable. `steps` is the
plan length, `writes` the number of attempted mutation requests.

每个用例都声明初始状态、目标、预期操作、预期退出状态，以及必须可独立查询的结果。
`steps` 是计划长度，`writes` 是尝试的修改请求数。

| Case / 用例 | Initial state / 初始状态 | Target / 目标 | Expected / 预期 |
| --- | --- | --- | --- |
| `converge` | `cmpveth` DOWN, MTU 1500, no managed addresses or routes / `cmpveth` DOWN、MTU 1500，无受管理地址与路由 | [converge.json](../demo/compare/desired/converge.json) | steps 6, writes 6, exit 0, MTU 1400 + UP + 2 addresses + 2 table-1000 routes verified / steps 6、writes 6、退出 0，MTU 1400、UP、2 个地址和 2 条表 1000 路由全部验证 |
| `repeat` | Already converged, plus an undeclared table-1000 route / 已收敛，另有一条未声明的表 1000 路由 | same as `converge` / 同 `converge` | steps 0, writes 0, exit 0, all resources still satisfied and preserved / steps 0、writes 0、退出 0，资源仍满足且未管理资源保留 |
| `preexisting` | MTU 1400 + UP + IPv4 address + IPv4 table-1000 route already exist / 已存在 MTU 1400、UP、IPv4 地址和 IPv4 表 1000 路由 | same as `converge` / 同 `converge` | steps 2, writes 2, exit 0, only the missing IPv6 address and route are written / steps 2、writes 2、退出 0，只写入缺失的 IPv6 地址和路由 |
| `unmanaged` | MTU 1500 UP, undeclared addresses on both interfaces and a main-table route sharing a declared prefix / MTU 1500 UP，两个接口上均有未声明地址，主表有一条与声明前缀相同的路由 | same as `converge` / 同 `converge` | steps 5, writes 5, exit 0, every undeclared resource still present / steps 5、writes 5、退出 0，所有未声明资源仍然存在 |
| `conflict` | Seed state / 种子状态 | [conflict.json](../demo/compare/desired/conflict.json) | rejected as `ConflictingIntent` before any write, exit nonzero, MTU unchanged / 在任何写入前以 `ConflictingIntent` 拒绝，非零退出，MTU 不变 |
| `protected-loopback` | `lo` UP / `lo` UP | [protected-loopback.json](../demo/compare/desired/protected-loopback.json) | rejected as `ProtectedResource`, exit nonzero, `lo` stays UP / 以 `ProtectedResource` 拒绝，非零退出，`lo` 保持 UP |
| `protected-default-route` | Seed state, no default route / 种子状态，无默认路由 | [protected-default-route.json](../demo/compare/desired/protected-default-route.json) | rejected as `ProtectedResource`, exit nonzero, no route added / 以 `ProtectedResource` 拒绝，非零退出，未添加路由 |
| `failure` | DOWN, MTU 1500, one undeclared address / DOWN、MTU 1500，一个未声明地址 | [failure.json](../demo/compare/desired/failure.json) | steps 7, writes 6, the sixth operation fails with kernel errno 101, operations 0–4 completed, operation 6 skipped, 5 reverse compensations, exit nonzero, desired state still unmet / steps 7、writes 6，第六项被内核以 errno 101 拒绝，0–4 完成、第 6 项未执行、5 项逆序补偿、非零退出，目标仍未达成 |

The acceptance matrix of the TODO also requires: dry-run changes nothing and
conflicting input is refused before writing; the first application reaches the
same managed fields; a repeated application performs zero writes; a kernel
refusal stops the remaining steps, exits nonzero, records partial completion,
compensates in reverse and re-verifies; resources outside the target are not
cleaned up; and an application can reliably judge the result and release its
resources.

TODO 的验收矩阵还要求：预演不产生任何修改，冲突输入在写入前拒绝；首次应用达到相同
的受管理字段；重复应用零写入；内核拒绝时停止后续步骤、非零退出、记录部分完成、逆序
补偿并重新核验；目标之外的资源不被清理；应用能可靠判断结果并释放资源。

## Contract check / 契约校验

The contract is checked independently of both implementations. The checker
re-derives the expected operations, rejections and final state from each case's
initial state and desired file, and fails if the declaration disagrees. It needs
no privileges, namespace or kernel, so it also runs on Windows.

契约的校验独立于双方实现。校验器从每个用例的初始状态与目标文件重新推导预期操作、
拒绝原因和最终状态，声明与推导不一致即失败。它不需要权限、命名空间或内核，因此在
Windows 上也可运行。

```sh
python3 demo/compare/check_contract.py
python3 demo/compare/check_contract.py --json
```

A successful run prints one line per case and exits zero:

成功运行时逐行输出每个用例并以零退出：

```text
converge                 apply   steps=6 writes=6 compensation=0 exit=0 rejection=-
repeat                   apply   steps=0 writes=0 compensation=0 exit=0 rejection=-
...
comparison contract: 8 case(s) consistent with the declared initial state and target
```

## Status and limits / 当前状态与限制

This page defines the standard. The script baseline (P5-V2/P5-V3), the MoonBit
application sample (P5-V4) and the automated two-sided verifier (P5-V5) are not
implemented yet, so this document makes no claim about their relative cost,
speed or maintainability. Performance measurements stay in the separate
`ip -j` baseline task and must not be mixed with this acceptance contract.

本页定义标准。脚本基线（P5-V2/P5-V3）、MoonBit 应用样例（P5-V4）和自动化双
方验收入口（P5-V5）尚未实现，因此本文不对它们的相对成本、速度或可维护性作任何主张。
性能测量仍属于独立的 `ip -j` 基线任务，不得与本验收契约混用。

The expected outcome of the `failure` case depends on the tested kernel
returning errno 101 for an unreachable gateway; the isolated verification
records the actual kernel error instead of assuming it.

`failure` 用例的预期结果取决于被测内核在网关不可达时返回 errno 101；隔离验证记录
实际内核错误，而不是假定它。
