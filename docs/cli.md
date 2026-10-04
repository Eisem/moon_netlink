# Query and event CLI / 查询与事件命令行

The `cmd/moonnet` executable exposes the four Phase 2 typed queries:

`cmd/moonnet` 可执行程序提供 Phase 2 的四种类型化查询：

```text
moonnet link show [--json]
moonnet address show [--json]
moonnet route show [--json]
moonnet neighbor show [--json]
```

From the source tree, use `moon run --target native cmd/moonnet --` before the
arguments. The commands are read-only and require Linux/native, but do not
normally require elevated privileges.

从源码目录运行时，在参数前使用 `moon run --target native cmd/moonnet --`。这些命令只读，需要 Linux/native，通常无需提升权限。

Human output is tab-separated and intended for inspection. `--json` emits one
JSON array with canonical IP/MAC strings, explicit `null` for absent values,
and ordinary JSON numbers for present numeric fields.

供人阅读的输出以制表符分隔，便于检查。`--json` 输出一个 JSON 数组，IP/MAC 使用规范化字符串，缺失字段明确输出 `null`，有值的数值字段输出普通 JSON 数字。

Output order is deterministic:

输出按以下确定性顺序排列：

- Link: interface index, then name;
   Link：接口索引、名称；
- Address: interface index, family, address, then prefix length;
   Address：接口索引、协议族、地址、前缀长度；
- Route: family, table, destination, prefix, output interface, then gateway;
   Route：协议族、表、目的地址、前缀、输出接口、网关；
- Neighbor: interface index, family, destination, then link-layer address.
   Neighbor：接口索引、协议族、目的地址、链路层地址。

Route tie-breakers include source prefix length, preferred source, input
interface, protocol, scope, type, TOS and flags. All fields rendered in Route
JSON participate in its ordering, so reversing the kernel's record order does
not change the output. Unknown attributes are preserved in the SDK but are
not emitted by this CLI.

Route 的进一步排序字段包括源前缀长度、首选源地址、输入接口、协议、作用域、类型、TOS 和标志。Route JSON 中输出的所有字段均参与排序，因此反转内核记录顺序不会改变结果。SDK 保留未知属性，但该 CLI 不输出它们。

## Watch / 监听

```text
moonnet watch [link|address|route|neighbor|all] [--jsonl]
```

The default filter is `all`; `--jsonl` can appear before or after the filter.
Duplicate filters/options and unknown arguments fail with a nonzero exit code.
`watch` opens an independent multicast socket and streams until cancelled or
an error occurs. It writes `moonnet watch: ready` to stderr after subscribing,
so scripts can generate events without guessing a startup delay.

默认过滤器是 `all`；`--jsonl` 可位于过滤器前后。重复的过滤器、选项或未知参数导致非零退出。`watch` 打开独立的组播 socket，持续输出直到取消或出错。订阅完成后向 stderr 写入 `moonnet watch: ready`，脚本可据此开始修改，无需猜测启动延迟。

JSONL writes one complete JSON object per line immediately, with two keys:

JSONL 即时逐行写入完整 JSON 对象，每个对象包含以下两个键：

```json
{"event":"address.added","object":{"family":"ipv4","interface_index":7,"interface_name":null,"prefix_length":24,"scope":0,"local_address":"192.0.2.10","address":"192.0.2.10","label":null,"flags":0}}
```

Event names are `link.changed`, `link.deleted`, `address.added`,
`address.deleted`, `route.added`, `route.deleted`, `neighbor.changed`,
`neighbor.deleted`, and `unknown`. Known objects use the corresponding query
JSON shape, including `ipv4`/`ipv6` family strings. Address/Neighbor interface
names are `null` because notifications contain indices. Unknown messages
expose message type, sequence, flags and payload as a byte-number array.
Events keep arrival order. Without `--jsonl`, the CLI writes the object kind
and typed debug representation.

事件名称为 `link.changed`、`link.deleted`、`address.added`、`address.deleted`、`route.added`、`route.deleted`、`neighbor.changed`、`neighbor.deleted` 和 `unknown`。已知对象采用对应查询的 JSON 形状，协议族用 `ipv4`/`ipv6` 字符串表示。地址和邻居通知只含接口索引，因此接口名称为 `null`。未知消息提供消息类型、序列号、标志及由字节数值组成的载荷数组。事件保留到达顺序；不使用 `--jsonl` 时输出对象类别和类型化调试表示。

Kernel failures display errno and available extack text/offset on stderr.
Event loss displays a request to query a fresh snapshot and exits nonzero;
the CLI does not reconnect silently. Monitor buffering and recovery rules are
documented in [transport.md](transport.md).

内核失败会在 stderr 显示 errno 和可用的 extack 文本、偏移。丢失事件时会提示重新查询快照并以非零状态退出，CLI 不会静默重连。缓冲与恢复规则见 [传输层说明](transport.md)。

## Plan and apply / 规划与应用

```text
moonnet plan desired.json [--json] [--dangerous]
moonnet apply desired.json [--json] [--dangerous]
moonnet apply desired.json --yes [--json] [--dangerous]
```

`plan` and unconfirmed `apply` perform the same read-only planning workflow.
Only `apply --yes` enables sequential execution, compensation on failure and
fresh desired-state verification. `plan --yes` and duplicate confirmation are
rejected. A regular UTF-8 configuration file is read with a 1 MiB limit before
opening a route socket. Schema and SDK validation errors remain structured.
Planning uses a fresh snapshot and shared safety validation. Loopback/default
route changes require explicit `--dangerous`, which alone does not execute them.
Preview JSON is the version-1 Plan shape; human output lists every exact
operation, reason and danger marker. Duplicate or unknown flags fail.

`plan` 与未确认的 `apply` 使用同一只读规划流程。只有 `apply --yes` 会启用顺序执行、失败补偿和重新观测目标状态。`plan --yes` 和重复确认均被拒绝。打开 route socket 前，先读取普通 UTF-8 配置文件，大小上限为 1 MiB。schema 与 SDK 校验保留结构化错误。规划使用新快照和共用的安全校验；修改回环接口或默认路由需要显式 `--dangerous`，该选项本身不会执行修改。预演 JSON 采用版本 1 的 Plan 结构；人读输出列出每项精确操作、原因和危险标记。重复或未知选项会失败。

Confirmed apply emits an ApplyReport (JSON or human) with completed, failed and
unexecuted steps, each compensation result and final verification. Reports go
to stdout before a nonzero exit for mutation failure, cancellation, unmet goals
or verification error. Preflight rejection reports its original error on stderr
before any write. See [reconcile.md](reconcile.md) for outcome uncertainty and
recovery limits. Run `bash .ci/validate-apply.sh` for a disposable namespace demo.

确认执行会输出 JSON 或人读形式的 ApplyReport，包含已完成、失败、未执行步骤，每项补偿结果及最终验证。修改失败、取消、目标未达成或验证出错时，先将报告写入 stdout，再以非零状态退出。执行前检查拒绝时，先在 stderr 报告原始错误，不进行任何写入。结果不确定性和恢复边界见 [收敛执行说明](reconcile.md)。可运行 `bash .ci/validate-apply.sh` 查看临时命名空间演示。
