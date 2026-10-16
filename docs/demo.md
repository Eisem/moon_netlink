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

## Five-minute comparison walkthrough / 约五分钟对照演示

Use the following sequence after dependency download and compilation have
completed. These are narration allocations, not measured runtimes: approximately
one minute for equivalent results, one for zero-write repetition, one for a real
failure and recovery, and two for application decisions. Slow hardware, missing
packages or kernel differences can take longer or fail; do not hide those outcomes.
Run from the repository root in the same Bash session. Alongside the dependencies
above, this sequence uses Bash 4+ and GNU `timeout` (coreutils). User/network
namespaces and IPv6 must work. Raw output stays under `_build/compare-presentation/`.
This is a source-checkout demonstration, not a published-package installation.

依赖下载与编译完成后，按以下顺序演示。时间仅为讲解安排，并非实测运行时间：相同结果
约一分钟，重复执行零写入约一分钟，真实失败及恢复约一分钟，应用判定约两分钟。硬件较慢、
缺包或内核差异可能使流程变慢或失败，不应隐藏。所有命令从仓库根目录、在同一 Bash 会话中
运行。除前述依赖外，使用 Bash 4+ 及 GNU `timeout`（coreutils）；用户与网络命名空间和
IPv6 必须可用。原始输出保留在 `_build/compare-presentation/`。此流程从源码检出目录
运行，不替代已发布包的安装验证。

Prepare before presenting; first-time checkouts also need `moon update`:

演示前完成准备；首次检出还需先运行 `moon update`：

```sh
set -euo pipefail
moon build --target native
python3 demo/compare/check_contract.py
```

### 1. Same target and result / 相同目标与结果

Run both implementations once against the three presentation cases. The shared
facility supplies equivalent but separate namespaces and observes each result
independently with `ip -j`. Both sides also run their own failure-handling checks.
The command returns zero only when the selected expectations and both sides'
observations agree. It is a selected-case run; omit `--case` for all eight cases.

对三个演示用例运行双方实现。共享设施提供等价但分离的命名空间，并通过 `ip -j` 独立
观测每侧结果。各侧也执行自己的失败处理检查。只有选定用例的预期满足且双方观测一致时，
命令才返回零。这是选定用例运行；去掉 `--case` 可验收全部八个用例。

```sh
bash demo/compare/run.sh \
  --case converge --case repeat --case failure \
  --timeout 180 --results _build/compare-presentation
```

Show the `converge` row marked `ok` for both sides, then display the saved
observations with the command below. For convergence, each side has six planned
and attempted mutations, successful verification and all declared resources
satisfied. Read the [fixed target](../demo/compare/desired/converge.json): MTU 1400,
UP, IPv4/IPv6 addresses and two table-1000 routes. No winner is required.

先展示 `converge` 行双方均为 `ok`，再用下面的命令显示保存的观测。首次收敛时双方计划及
尝试修改均为六项，最终核验成功，声明资源全部满足。[固定目标](../demo/compare/desired/converge.json)
为 MTU 1400、UP、IPv4/IPv6 地址及两条表 1000 路由。通过条件不要求某一方胜出。

```sh
python3 - <<'PY'
import json
from pathlib import Path
root = Path('_build/compare-presentation')
for name in ('converge', 'repeat', 'failure'):
    for side in ('script', 'app'):
        results = json.loads((root / (side + '.json')).read_text())
        case = next(item for item in results['cases'] if item['id'] == name)
        observed = case['observed']
        print(json.dumps({
            'case': name, 'side': side, 'status': case['status'],
            'steps': len(observed['plan']),
            'attempted_writes': observed['attempted_writes'],
            'completed': observed['completed'],
            'failed_index': observed['failed_index'],
            'not_executed': observed['not_executed'],
            'compensations': observed['compensations'],
            'verified': observed['verification_satisfied'],
            'resource_checks': observed['satisfied'],
            'preserved': all(observed['preserved']),
        }))
PY
```

### 2. Repeated application / 重复应用

Read the `repeat` records from the same output: `steps=0`, `attempted_writes=0`,
`verified=true`, and preservation remains true. A socket send counter measures
SDK writes; the Bash baseline counts attempted mutation commands. Missing counts
fail acceptance. This fixture reseeds an already converged topology, including an undeclared
route; it does not continue the previous case's apply. To separately show a first
apply followed by a second empty plan in the same namespace, run
`bash demo/reconcile.sh` outside this short presentation.

在同一输出中读取 `repeat` 记录：`steps=0`、`attempted_writes=0`、`verified=true`，
保留资源也仍满足。SDK 写入由 socket 发送计数测量，Bash 基线记录尝试的修改命令；缺少
计数即验收失败。该用例重新预置包含未声明路由的已收敛拓扑，不接续前一用例的 apply。
如需另外展示同一命名空间内首次 apply 后第二次计划为空，可在此简短演示之外运行
`bash demo/reconcile.sh`。

### 3. Real mid-plan rejection / 真实中途拒绝

Read the `failure` records: seven planned steps, six mutation attempts, completed
indices `[0,1,2,3,4]`, failed index `5`, unexecuted `[6]`, and compensation order
`[4,3,2,1,0]`. Verification stays false because recovery is not convergence; preserved
resources remain present. The [runner](../demo/compare/run_cases.py) requires the
actual application process to exit nonzero, checks SDK errno 101 and the script's
nonempty original command diagnostic, then independently observes the result.
Its outer acceptance command exits zero because the expected failure was verified.
The baseline cannot recover numeric errno from iproute2's exit code.

读取 `failure` 记录：计划七步，尝试修改六次，完成索引 `[0,1,2,3,4]`、失败索引 `5`、
未执行 `[6]`、补偿顺序 `[4,3,2,1,0]`。最终核验为假，因为恢复不等于目标达成；需要保留
的资源仍存在。[运行器](../demo/compare/run_cases.py)要求实际应用进程非零退出，核对 SDK
的 errno 101 和脚本非空的原始命令诊断，再独立观测结果。外层验收命令返回零，是因为已
验证这次预期失败。基线不能从 iproute2 退出码恢复数字 errno。

Recovery is best effort over supported fields. Unknown operations are reported
without assuming they did not take effect; only acknowledged completed steps are
compensated. Compensation can fail, and SIGKILL cannot trigger cleanup in the
application. The isolated fixture disappears after its last process exits. See
[recovery boundaries](comparison.md) rather than describing this as a transaction.

恢复仅对受支持字段尽力执行。结果不明的操作会被报告，不假定其未生效；只补偿已确认完成
的步骤。补偿可能失败，SIGKILL 无法触发应用内清理。隔离测试环境在最后进程退出后消失。
应结合[恢复边界](comparison.md)解释，不应将其称为事务。

### 4. Application reads the report / 应用读取报告

Show `conditions_of`, `classify`, `emit` and the client-closing defer in the
[application](../examples/network_config_app/main.mbt). The application receives a
typed `ApplyReport` from `reconcile.reconcile`; JSON is its presentation format,
not the integration API. Upstream async owns task/fd facilities, MoonNetlink owns
the networking workflow, and the application owns its business decision. The
[responsibility inventory](comparison.md) also includes script helpers, simulation
code and shared test facilities, with no source-line efficiency multiplier.

展示[应用源码](../examples/network_config_app/main.mbt)中的 `conditions_of`、`classify`、
`emit` 及关闭 client 的 defer。应用从 `reconcile.reconcile` 接收类型化 `ApplyReport`；
JSON 是展示格式，不是进程内接入 API。上游 async 负责任务及 fd 设施，MoonNetlink 负责
网络流程，应用负责业务判定。[职责清单](comparison.md)还计入脚本辅助工具、模拟代码及
共享测试设施，不用源码行数推导效率倍数。

To show the actual decision documents, create a separate disposable fixture and
run the four labelled simulations. Every application exits nonzero; its JSON and
stderr are retained. The 30-second outer timeout bounds this extra demonstration.
All mutations are simulated; observations still query the real isolated kernel.

为了展示实际判定文档，另建可丢弃环境，运行四类明确标记的模拟。每个应用均非零退出，
JSON 和 stderr 均保留；外层 30 秒超时限制这段附加演示。所有修改均模拟，观测仍查询真实的
隔离内核。

```sh
timeout --kill-after=2s 30s unshare -Urn -- bash <<'SH'
set -euo pipefail
ip link set lo up
ip link add cmpveth type veth peer name cmppeer
ip link set cmppeer up
app=_build/native/debug/build/examples/network_config_app/network_config_app.exe
for mode in partial unknown compensation target-unmet; do
  status=0
  "$app" apply demo/compare/desired/converge.json --simulate "$mode" --json \
    > "_build/compare-presentation/application-$mode.json" \
    2> "_build/compare-presentation/application-$mode.err" || status=$?
  test "$status" -ne 0
done
SH

python3 - <<'PY'
import json
from pathlib import Path
root = Path('_build/compare-presentation')
expected = {'partial': 'partial', 'unknown': 'outcome-unknown',
            'compensation': 'compensation-failed', 'target-unmet': 'target-unmet'}
for mode, decision in expected.items():
    data = json.loads((root / ('application-' + mode + '.json')).read_text())
    audit = (root / ('application-' + mode + '.err')).read_text().splitlines()
    assert data['scenario'] == 'simulated:' + mode
    assert data['decision'] == decision
    assert audit.count('moonnetlink-mutation-attempts:0') == 1
    print(json.dumps({'scenario': data['scenario'], 'decision': data['decision'],
                      'conditions': data['conditions'], 'kernel_mutation_attempts': 0}))
PY
```

Expected decisions are `partial`, `outcome-unknown`, `compensation-failed` and
`target-unmet`. In the last case `execution_completed=true` but `verified=false`:
acknowledged operations do not establish desired state. These four failures are
simulation evidence only; the earlier `failure` contract case is the real kernel
rejection. The wrapper's success means all expected application failures were
observed, not that the target converged.

预期判定依次为 `partial`、`outcome-unknown`、`compensation-failed`、`target-unmet`。
最后一种 `execution_completed=true` 但 `verified=false`：确认全部操作不代表目标达成。
这四类仅为模拟失败证据；前面的 `failure` 契约用例才是真实内核拒绝。包装流程成功表示
观测到了全部预期应用失败，不表示目标已收敛。

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
