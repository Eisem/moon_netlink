# Ordered reconciliation / 顺序状态收敛

`NetworkBackend` separates observable snapshots and bounded acknowledged
mutations. `RouteBackend::new(client)` adapts the public SDK; callers close the
client. It rechecks interface name/index immediately before each SDK mutation,
but cannot make kernel changes atomic or stop independent writers.

`NetworkBackend` 将可观测快照与有界、需确认的修改分离。`RouteBackend::new(client)` 适配公共 SDK，由调用者关闭 client。每次 SDK 修改前立即重新检查接口名称、索引，但不能使内核修改原子化，也不能阻止独立写入者。

`apply_plan(backend, plan, dry_run=true, dangerous=false)` owns a copy of the
step array and runs shared whole-plan protection before any mutation. Explicit
execution follows Plan order and stops on its first error. `ApplyReport` exposes
acknowledged indices, the original typed error, remaining indices, dry-run and
cancellation state. JSON preserves kernel errno/extack fields. Optional extack
message/offset and observed interface index use ordinary strings/numbers when
present and `null` when absent. An unknown
failed-operation outcome is marked explicitly; a timeout can follow a successful
kernel write. Acknowledgement does not prove that desired state was achieved.

`apply_plan(backend, plan, dry_run=true, dangerous=false)` 拥有步骤数组的副本，修改前执行共用的整计划保护。显式执行遵循 Plan 顺序，首个错误即停止。`ApplyReport` 提供已确认索引、原始类型化错误、剩余索引、预演与取消状态。JSON 保留内核 errno、extack 字段；可选 extack 文本、偏移和观测接口索引存在时输出普通字符串或数字，否则为 `null`。失败操作结果未确定时会明确标记；内核写入成功后仍可能发生超时。收到确认不证明目标状态已达成。

Mutations are shielded from caller cancellation until their bounded SDK request
finishes; cancellation between steps stops execution. Custom backends must bound
their own operations. On failure or cancellation, completed operations are
compensated in reverse order under cancellation protection. Compensation errors
are recorded without hiding the original error or stopping later compensations.
Unobserved previous MTU is explicitly unavailable. An unacknowledged failed
operation is never blindly compensated because its outcome may be unknown.

修改期间屏蔽调用者取消，直到有界 SDK 请求结束；步骤间取消则停止执行。自定义 backend 必须限制自身操作时长。失败或取消后，在取消保护下按逆序补偿已完成操作。补偿错误逐项记录，不掩盖原始错误，也不阻止后续补偿。未观测到的旧 MTU 明确标为无法补偿；未经确认的失败操作结果可能未确定，绝不盲目补偿。

Compensation restores supported managed fields/identities, not arbitrary kernel
metadata, address lifetimes or implicit connected-route effects. Independent
writers can make compensation fail. This is best-effort recovery, not an atomic
transaction.

补偿恢复受支持的管理字段和身份，不恢复任意内核元数据、地址生命周期或隐式直连路由效果。独立写入者可能使补偿失败。这是尽力恢复，不是原子事务。

`reconcile(backend, desired, dry_run=true, dangerous=false)` owns the desired
arrays, builds a fresh plan, executes it with the same safeguards, and queries
again after execution or compensation. Verification contains the observation,
remaining plan or its original read/comparison error. `succeeded()` requires
acknowledged execution and an empty final desired-state difference; it remains
false after a mutation failure, cancellation, unmet goals or verification error.
Dry-run has no final verification. The lower-level `apply_plan` reports ACKs
only, so its `succeeded()` is always false without a desired-state verification.
A verification error alone does not blindly compensate already acknowledged
changes; the report exposes the uncertainty for caller recovery.

`reconcile(backend, desired, dry_run=true, dangerous=false)` 拥有目标数组副本，构建新计划，以同样保护执行，并在完成执行或补偿后再次查询。验证结果包含观测、剩余计划或原始读取、比较错误。`succeeded()` 要求执行被确认且最终目标差分为空；修改失败、取消、目标未满足或验证错误均返回 false。预演不做最终验证。底层 `apply_plan` 仅报告 ACK，因此没有目标状态验证时，其 `succeeded()` 始终为 false。仅验证出错不会盲目补偿已确认修改；报告暴露不确定性，由调用者决定恢复。

`bash .ci/validate-idempotence.sh` applies MTU/UP, IPv4/IPv6 addresses and
nondefault routes in a disposable namespace, compares queries with `ip -j`,
then requires an empty second plan and no-op second apply. Explicit deletion
also converges, while undeclared addresses and routes remain present.
Unmanaged-route comparison retains every field and flag except `linkdown`:
changing one veth endpoint's UP state changes peer carrier, so this marker is
expected to change while the peer's configured route remains unchanged.

`bash .ci/validate-idempotence.sh` 在临时命名空间应用 MTU/UP、IPv4/IPv6 地址和非默认路由，与 `ip -j` 对拍，然后要求第二次计划为空、第二次 apply 无操作。显式删除也会收敛，未声明地址和路由仍保留。对未管理路由的比较保留所有字段和标志，仅排除 `linkdown`：改变 veth 一端的 UP 状态会改变对端载波，因而该标记应变化，但对端配置的路由不变。

`bash .ci/validate-failures.sh` proves conflicting intent and default-route
protection reject before any write. It then deletes an old address/route,
changes MTU/UP and adds new resources before an unreachable gateway triggers
kernel errno 101. The CLI must report completed/skipped operations, compensate
in reverse, restore the supported original configuration, and show the final
desired state remains unmet. Both JSON and human failures exit nonzero. Separate
backend tests prove compensation errors remain visible and do not hide the cause.

`bash .ci/validate-failures.sh` 证明意图冲突和默认路由保护均在写入前拒绝。随后删除旧地址、路由，修改 MTU/UP 并添加新资源，直到不可达网关触发真实内核 errno 101。CLI 必须报告完成、跳过操作，逆序补偿，恢复受支持的原配置，并显示最终目标仍未满足。JSON 和人读失败均非零退出。独立 backend 测试证明补偿错误保持可见且不掩盖原始原因。
