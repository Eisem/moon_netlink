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

## Script baseline / 脚本基线

`demo/compare/script/baseline.sh` implements the same subset with Bash,
iproute2 and one declared JSON tool. Bash owns argument handling, dependency
checks, sequencing, command execution, write accounting, exit status and
cleanup; the JSON tool owns strict validation, the plan and report documents,
the exact `ip` argv of every step and the independent `ip -j` comparison. The
baseline never calls MoonNetlink and never parses human-readable `ip` output.

`demo/compare/script/baseline.sh` 使用 Bash、iproute2 和一个明确声明的 JSON 工具实现
同一输入子集。Bash 负责参数处理、依赖检查、顺序编排、命令执行、写计数、退出状态和
清理；JSON 工具负责严格校验、计划与报告文档、每一步的 `ip` 参数，以及独立的
`ip -j` 比较。基线从不调用 MoonNetlink，也不解析人类可读的 `ip` 输出。

| Item / 项目 | Value / 取值 |
| --- | --- |
| Invocation / 调用 | `bash demo/compare/script/baseline.sh plan\|apply\|verify <config.json> [--yes] [--json] [--dangerous]` |
| Dependencies / 依赖 | bash 4+, iproute2 `ip`, python3 3.8+ as the declared JSON tool / bash 4+、iproute2 `ip`、python3 3.8+ 作为声明的 JSON 工具 |
| Exit status / 退出状态 | 0 reached and verified, 1 rejected or not reached, 2 usage error, 3 missing dependency or observation failure / 0 达成并验证，1 被拒绝或未达成，2 用法错误，3 缺少依赖或观测失败 |
| Plan document / 计划文档 | `schema_version`, `steps[].change` with the documented operation parameters, `reason`, `dangerous` / 含契约文档化的操作参数、原因与危险标记 |
| Report document / 报告文档 | `completed`, `failed`, `not_executed`, `rollback`, `attempted_writes`, `compensations`, `verification`, `succeeded` |
| Rejection / 拒绝 | structured JSON on stderr with the contract's category and `attempted_writes: 0`; stdout stays empty like the SDK CLI / stderr 输出含契约类别与 `attempted_writes: 0` 的结构化 JSON；stdout 与 SDK CLI 一样保持为空 |

`apply` without `--yes` prints exactly the same plan document as `plan`, so the
dry-run property can be checked on both sides. Every attempted mutation is
counted, so a repeated run that writes nothing is proven instead of inferred
from the final state. Both sides also emit `moonnetlink-mutation-attempts:<n>`
on stderr, including plans and pre-write rejections. The runner requires this
measurement; missing evidence fails acceptance.

`apply` 未传 `--yes` 时输出与 `plan` 完全相同的计划文档，因此预演性质在双方都可校验。
每次尝试的修改都被计数，因此重复执行零写入是经过证明的，而不是由最终状态推断。双方也在 stderr
输出 `moonnetlink-mutation-attempts:<n>`，包括计划和写入前拒绝路径。运行器必须收到该
测量值；缺少证据即验收失败。

Two differences are already measured and recorded rather than hidden:

已经测量并记录、而不是被隐藏的两处差异：

- `ip(8)` collapses every kernel refusal into exit status 2, so the baseline
  reports the kernel diagnostic text and a failed command, not a numeric errno;
  the SDK reports the kernel errno (for example 101) and extended ACK fields.
  `ip(8)` 把所有内核拒绝都折叠为退出码 2，因此基线报告内核诊断文本和失败命令，而不是
  数字 errno；SDK 报告内核 errno（例如 101）和扩展 ACK 字段。
- `ip(8)` can express only the five named address scopes, so the baseline
  rejects any other declared scope as `UnsupportedIntent` before writing, while
  the SDK can set arbitrary `IFA_SCOPE` values. No contract case uses one.
  `ip(8)` 只能表达五个具名地址作用域，因此基线在写入前把其他作用域声明按
  `UnsupportedIntent` 拒绝，而 SDK 可设置任意 `IFA_SCOPE` 值。契约用例不使用这类取值。

The mid-plan failure path is implemented. A failing command stops execution
immediately; the plan document, computed from the observation taken before the
first write, is the recorded pre-change state; acknowledged operations are then
compensated in reverse order, a failing compensation is recorded without
stopping the remaining ones, and the actual state is observed again. A command
terminated by a signal is reported as an unknown outcome and is deliberately
not compensated. SIGTERM or SIGINT stops execution at the next step boundary
and still compensates. Recovery restores supported managed fields and
identities only, so it is best effort and not an atomic transaction; SIGKILL
cannot be compensated at all.

中途失败路径已实现：命令失败立即停止；由首次写入前的观测生成的计划文档即所记录的修改前
状态；随后对已确认操作逆序补偿，某次补偿失败会被记录且不阻止后续补偿，最后重新观测实际
状态。被信号终止的命令报告为结果不明，并有意不做补偿。SIGTERM 或 SIGINT 会在下一个
步骤边界停止执行并仍然补偿。恢复只针对受支持的管理字段和身份，因此属于尽力而为，不是
原子事务；SIGKILL 完全无法补偿。

Run it against the contract cases inside a disposable namespace:

在临时命名空间中按契约用例运行：

```sh
bash demo/compare/check.sh                    # every case plus the extra checks
bash demo/compare/check.sh --case repeat      # one case
```

The runner seats each case's declared initial state through iproute2, runs the
baseline for the read-only plan, the unconfirmed apply and the confirmed apply,
and compares plan, report and the independent `ip -j` observation with the
contract. Beyond the contract cases it checks two interruption behaviours with
a deterministic `ip` shim that reacts to the third mutation: a SIGTERM between
steps must compensate the acknowledged operations, and a signal-terminated
command must be reported as an unknown outcome without being compensated. It
refuses to run when the network namespace equals the caller's.

运行器通过 iproute2 建立每个用例声明的初始状态，先后运行只读预演、未确认 apply 和
确认 apply，并把计划、报告与独立的 `ip -j` 观测同契约比较。除契约用例外，它还用一个
对第三次修改作出反应的确定性 `ip` 替身检查两种中断行为：步骤之间的 SIGTERM 必须补偿
已确认操作；被信号终止的命令必须报告为结果不明且不被补偿。当网络命名空间与调用者相同时
拒绝运行。

## Application sample / 应用接入样例

`examples/network_config_app/` is an application, not a CLI wrapper. It reads a
declared target with `state.DesiredState::parse`, observes the network through
`transport.RouteClient`, reviews the plan with `state.build_plan` and
`state.validate_plan`, executes it with `reconcile.reconcile` and judges the
returned `ApplyReport` in process. It never shells out and never copies library
internals; the enclosing task group closes the client.

`examples/network_config_app/` 是应用样例，而不是 CLI 包装。它用
`state.DesiredState::parse` 读取目标，用 `transport.RouteClient` 观测网络，用
`state.build_plan` 与 `state.validate_plan` 审查计划，用 `reconcile.reconcile` 执行，
并在进程内判断返回的 `ApplyReport`。它不调用外部命令，也不复制库内部实现；由外层任务组
负责关闭 client。

| Item / 项目 | Value / 取值 |
| --- | --- |
| Invocation / 调用 | `network_config_app plan <config.json> [--json] [--dangerous]`; `network_config_app apply <config.json> [--yes] [--json] [--dangerous] [--simulate <scenario>]` |
| Exit status / 退出状态 | 0 for a read-only plan or a converged target; nonzero for a refusal or an unmet target / 只读计划或已达成目标为 0；被拒绝或目标未达成为非零 |
| Document / 文档 | `schema_version`, `application`, `scenario`, `decision`, `conditions` and `report` (the library's `ApplyReport` JSON) |
| Decisions / 判定 | `dry-run`, `converged`, `target-unmet`, `partial`, `outcome-unknown`, `compensation-failed`, `interrupted` |
| Conditions / 条件 | `execution_completed`, `verified`, `compensation_complete`, `outcome_unknown`, `cancelled` |

An unconfirmed `apply` prints exactly the plan document that `plan` prints and
writes nothing. The application decides from the report: acknowledged execution
is not success unless a fresh observation satisfies the target.

未确认的 `apply` 输出与 `plan` 完全相同的计划文档且不写入。应用依据报告判定：仅收到
确认不算成功，必须由重新观测确认目标达成。

`--simulate` runs against `SimulatedBackend`, an implementation of the public
`NetworkBackend` trait that observes the real kernel but answers every mutation
from a fixed scenario. Those runs are labelled `scenario: simulated:<name>` and
never send a mutation, so failure handling stays reproducible without touching
the network. The scenarios are `partial` (determinate kernel rejection followed
by reverse compensation), `unknown` (an operation without a determinate result,
deliberately not compensated), `compensation` (recovery itself fails) and
`target-unmet` (every operation acknowledged while the target stays unmet).

`--simulate` 使用 `SimulatedBackend`，它是公共 `NetworkBackend` trait 的实现：观测真实
内核，但所有修改都由固定场景回答。这些运行标注为 `scenario: simulated:<name>`，且从不
发送修改，因此失败处理可复现且不触碰网络。场景包括 `partial`（结果确定的内核拒绝并逆序
补偿）、`unknown`（结果不确定的操作，有意不补偿）、`compensation`（恢复本身失败）和
`target-unmet`（全部操作被确认但目标仍未达成）。

Run the sample against the same contract cases and the simulated scenarios:

在同一契约用例与模拟场景下运行该样例：

```sh
bash demo/compare/check.sh --side app
```

## Two-sided acceptance / 双方验收入口

```sh
bash demo/compare/run.sh
```

One command runs both sides against the same contract. Each side gets its own
disposable user and network namespace, a fresh case state and a bounded run
(default 900 s); when the bound expires the whole process group of that side is
terminated, so no listener or namespace process survives. Raw results are saved
as `<dir>/<side>.json`, `<dir>/<side>.err` and `<dir>/report.txt`, by default
under `_build/compare/<utc>/`; `--results` changes the directory.

一条命令在同一契约下运行双方。每一方都获得独立的临时用户/网络命名空间、全新的用例状态
和有界运行时间（默认 900 秒）；超时会终止该方整个进程组，不留下监听进程或命名空间进程。
原始结果保存为 `<dir>/<side>.json`、`<dir>/<side>.err` 和 `<dir>/report.txt`，默认位于
`_build/compare/<utc>/`，可用 `--results` 更改目录。

The report prints one row per case plus the recorded notes, and the entry exits
zero only when both sides pass every case and both observed the same contract
values. A side "winning" is not a pass condition. Missing dependencies or
namespace privileges fail explicitly and never fall back to the caller's network
namespace. `--case <id>`, `--sides <list>` and `--timeout <sec>` narrow or bound
the run.

报告逐行显示每个用例与已记录的说明；只有当双方通过全部用例且观测到相同的契约值时，入口
才以零退出。“某一方胜出”不是通过条件。缺少依赖或命名空间权限会显式失败，绝不回退到调用
者的网络命名空间。`--case <id>`、`--sides <list>` 与 `--timeout <sec>` 可缩小或限制运行。

The table also shows the side-specific checks: `cancellation` and
`unknown-outcome` for the script baseline, `simulated-outcomes` for the
application sample. Side-specific checks appear as `n/a` on the other side. Required contract
observations may not be omitted; only the documented diagnostic differences
appear as notes.

表格也显示各方特有的检查：脚本基线为 `cancellation` 与 `unknown-outcome`，应用样例为
`simulated-outcomes`。某侧专属检查在另一侧显示为 `n/a`。必需的契约观测不得缺失；只有文档声明的诊断差异
以说明形式呈现。

## Acceptance integrity / 验收完整性

The Python runner exits before creating an implementation side or changing the
fixture if namespace isolation is absent or matches the caller. Unknown case
names and an empty selection are errors. The result comparer requires every
requested contract case and each selected side's own extra checks exactly once;
missing cases, failed statuses, malformed results and missing required
observations fail even when both sides omit the same evidence. `--case` is
passed to the comparer so an intentional subset remains verifiable.

Python 运行器在命名空间隔离信息缺失或仍处于调用者命名空间时，会在创建实现侧实例及
修改测试环境之前退出。未知用例名和空选择均为错误。汇总器要求所有请求的契约用例及各侧
专属附加检查恰好出现一次；缺失用例、失败状态、格式错误和缺失必需观测均会失败，即使
双方遗漏同一份证据也不例外。`--case` 同时传给汇总器，使有意缩小的范围仍可核验。

The SDK counts mutation attempts immediately before the socket write in
`RouteSocket.request_ack`; queries and failures before sending are excluded.
`RouteClient.mutation_attempts` exposes the cumulative count. With a dedicated
client, `RouteBackend` supplies it to reconciliation, whose report measures
forward `attempted_writes` separately from `compensations`. A custom backend
may implement `NetworkBackend.mutation_attempts`; its default returns `None`,
and reports serialize unavailable counts as null rather than deriving them
from completed or failed operations. Simulated runs separately prove zero real
kernel writes through the application's stderr measurement.

SDK 在 `RouteSocket.request_ack` 的 socket 写入之前记录修改尝试，不计查询和发送前
失败。`RouteClient.mutation_attempts` 公开累计计数。使用独立 client 时，`RouteBackend`
把该计数提供给协调器，报告分别测量正向 `attempted_writes` 和补偿 `compensations`。
自定义后端可实现 `NetworkBackend.mutation_attempts`；默认返回 `None`，报告将不可用
计数序列化为 null，不再从完成或失败操作推算。模拟运行另由应用的 stderr 测量值证明
真实内核写入为零。

Run the acceptance-integrity regression tests without privileges:

以下验收完整性回归测试无需权限：

```sh
python3 -m unittest discover -s demo/compare -p test_acceptance.py
```

## Status and limits / 当前状态与限制

This page defines the standard. The script baseline (P5-V2/P5-V3), the MoonBit
application sample (P5-V4) and the two-sided entry point (P5-V5) are implemented
and checked against the contract, including reverse compensation,
unknown-outcome reporting, simulated failure handling and cross-side agreement.
The publishable value narrative and the five-minute demonstration flow (P5-V6)
are not written yet, so this document still makes no claim about the two sides'
relative cost or maintainability, and the separate performance baseline remains
outstanding. Performance measurements stay out of this acceptance contract.

本页定义标准。脚本基线（P5-V2/P5-V3）、MoonBit 应用样例（P5-V4）和双方入口（P5-V5）
已实现并按契约校验，包含逆序补偿、结果不明报告、模拟失败处理和双方一致性核对。可发布的
价值说明与约五分钟演示流程（P5-V6）尚未撰写，因此本文仍不对双方的相对成本或可维护性作
任何主张，独立的性能基线也仍待完成。性能测量不属于本验收契约。

The expected outcome of the `failure` case depends on the tested kernel
returning errno 101 for an unreachable gateway; the isolated verification
records the actual kernel error instead of assuming it.

`failure` 用例的预期结果取决于被测内核在网关不可达时返回 errno 101；隔离验证记录
实际内核错误，而不是假定它。
