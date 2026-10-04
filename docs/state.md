# Declarative state model / 声明式状态模型

`state` is pure and depends on `route`, with no socket or async dependency.
`NetworkSnapshot::new` copies Link/Address/Route/Neighbor collections and their
unknown-attribute collections, preserving every domain field. Immutable
payload bytes remain owned values.

`state` 是纯逻辑包，只依赖 `route`，不依赖 socket 或 async。`NetworkSnapshot::new` 复制 Link、Address、Route、Neighbor 集合及其未知属性集合，保留所有领域字段；不可变载荷字节仍是拥有数据所有权的值。

Names identify desired links; indices reference objects in an observation.
`interface_name` and `link_by_name` return `None` for missing/unnamed objects.
A caller collects four dumps and constructs the snapshot. These observations
are not an atomic kernel snapshot.

名称用于识别目标链路，索引用于引用观测中的对象。对象缺失或未命名时，`interface_name` 和 `link_by_name` 返回 `None`。调用者收集四种导出并构造快照；这些观测不构成原子内核快照。

`normalize` copies and sorts all collections, using link/interface name then
complete raw fields as tie-breakers. It resolves Address/Neighbor names from
the observed links, without changing the input. `to_json` always normalizes and
emits schema version 1, canonical IP text and explicit nulls. Each object also
includes raw typed Debug text containing every field and unknown attribute;
that debug text is diagnostic, not a stable schema for application parsing.
Default destinations are explicit zero addresses only for prefix zero. The
supported route subset normalizes an absent metric to IPv4 zero / IPv6 1024.

`normalize` 复制并排序所有集合，先按链路、接口名称，再用完整原始字段打破相同排序值；它从观测链路解析 Address、Neighbor 名称，不修改输入。`to_json` 总会规范化，输出 schema 版本 1、规范化 IP 文本和明确的 null。每个对象还包含涵盖全部字段与未知属性的类型化 Debug 文本，用于诊断，不是供应用解析的稳定 schema。仅当前缀为零时，缺失的默认路由目的地址才规范化为全零地址。支持的路由子集将缺失 metric 规范化为 IPv4 的 0、IPv6 的 1024。

`moonnet snapshot` collects four read-only dumps and emits JSON. Volatile
fields can change between samples; byte determinism means identical input
observations give identical output, not that a live network remains static.

`moonnet snapshot` 收集四种只读导出并输出 JSON。易变字段可能在采样间变化；字节级确定性指相同输入观测产生相同输出，并不意味着实时网络保持静止。

## Desired schema version 1 / 目标配置 schema 版本 1

`DesiredState::parse` accepts `schema_version: 1` and optional `links`,
`addresses`, `routes` arrays (at most 1024 each). Every resource requires
`ensure: present|absent`. Link fields are `name`, optional boolean `up` and
positive u32 `mtu`; addresses require `interface`, IP `address` and numeric
`prefix_length`, with optional byte `scope` (default 0). Routes require
`interface`, canonical IP `destination`, numeric `prefix_length`; optional
`gateway` is an IP string, `table` defaults to 254, `protocol` to 4, `priority`
to IPv4 0 / IPv6 1024. IPv4 direct-route scope defaults to 253, others to 0.
Explicit IPv6 priority zero also means the kernel user-route default 1024.

`DesiredState::parse` 接受 `schema_version: 1` 和可选的 `links`、`addresses`、`routes` 数组，每类最多 1024 项。每个资源必须指定 `ensure: present|absent`。Link 字段为 `name`，以及可选布尔值 `up`、正值 u32 `mtu`；Address 要求 `interface`、IP `address` 和数值 `prefix_length`，可选字节 `scope` 默认 0。Route 要求 `interface`、规范化 IP `destination` 和数值 `prefix_length`；可选 `gateway` 为 IP 字符串，`table` 默认 254，`protocol` 默认 4，`priority` 默认 IPv4 的 0、IPv6 的 1024。IPv4 直连路由 scope 默认 253，其他默认 0；显式 IPv6 priority 0 也表示内核用户路由默认值 1024。

Numeric fields require unsigned decimal integer literals (`0` or digits);
decimal points, exponents and minus signs are rejected before conversion.
This prevents Double rounding or underflow from silently accepting a fraction.
Quoted strings such as IP addresses are unaffected.

数值字段必须是无符号十进制整数字面量（`0` 或数字序列），转换前拒绝小数点、指数和负号，避免 Double 舍入或下溢使小数被静默接受。IP 等带引号的字符串不受影响。

Unknown keys, wrong types, noninteger/out-of-range numbers, invalid names,
family/prefix mismatches and noncanonical routes fail. Repeated resource
identities are rejected, including opposite ensure intents. `validate_desired`
also checks typed SDK callers. Schema errors contain field paths; JSON syntax
and IP/route validation retain their original error types. JSON nesting and
input size are bounded. Parsing uses the core JSON parser's object-key rules.

未知键、错误类型、非整数或越界数值、非法名称、协议族与前缀不匹配、非规范化路由均失败。重复资源身份被拒绝，包括相反的 ensure 意图。`validate_desired` 也检查类型化 SDK 调用者。schema 错误带字段路径；JSON 语法和 IP、路由校验保留原始错误类型。JSON 嵌套和输入大小均有上限，对象键处理遵循 core JSON 解析器规则。

`evaluate_intent` considers only explicitly declared resources. Present means
the declared identity and supported fields match; absent means that identity
does not exist. Missing interfaces satisfy absent Address/Route intents but
fail present intent before planning. IPv6 address matching uses IFA_ADDRESS
when IFA_LOCAL is absent; default-route destination/priority are normalized.
Unspecified resources, flags and link fields remain unmanaged.

`evaluate_intent` 只考虑显式声明的资源。present 表示声明的身份和支持字段匹配；absent 表示该身份不存在。接口缺失时，absent Address、Route 意图成立，但 present 意图在规划前失败。IPv6 地址匹配在缺少 IFA_LOCAL 时使用 IFA_ADDRESS；默认路由目的地址和优先级被规范化。未指定的资源、标志和链路字段不受管理。

Link creation/deletion is outside the SDK subset, so absent Link is explicitly
rejected; `up=false` requests disabling an existing link. Existing point-to-point
addresses, mismatched scope/protocol or unsupported route features fail instead
of constructing a mutation that cannot reproduce their semantics. Migration
of unsupported properties requires a future explicit API, not implicit deletion.

链路创建、删除不在 SDK 子集内，因此 absent Link 被明确拒绝；`up=false` 表示禁用已有链路。已存在的点对点地址、不匹配的 scope/protocol 或不支持的路由特性会失败，不会生成无法重现其语义的修改。不支持属性的迁移需要未来显式 API，不通过隐式删除实现。

`diff(snapshot, desired)` returns supported typed `Change` values after complete
preflight. Link changes retain before/after values; Address/Route changes carry
exact SDK specs and resolved indices. Satisfied fields produce no change.
Unmanaged resources never generate deletions. Competing route slots or local
addresses reject exclusive adds unless the old identity is explicitly absent.
Two present route intents for one kernel slot conflict, even with different
gateways/interfaces. An explicit delete/add migration is permitted. Diff order
is deterministic but dependency ordering belongs to `Plan`; no I/O is performed.

`diff(snapshot, desired)` 在完整执行前检查后返回支持的类型化 `Change`。Link 修改保留前后值，Address、Route 修改携带精确 SDK spec 和解析后的索引；已满足字段不生成修改，未管理资源不会生成删除。同路由槽位或本地地址竞争时，除非旧身份被显式声明为 absent，否则拒绝排他添加。同一内核槽位的两个 present Route 意图会冲突，即使网关或接口不同；允许显式 delete/add 迁移。Diff 顺序确定，但依赖排序由 `Plan` 负责，整个过程不执行 I/O。

`build_plan(snapshot, desired)` orders route deletions, address deletions, MTU
preparation, Link UP, address additions, route additions, then Link DOWN.
Full change values break ties, so input order cannot change the plan. Every
step includes a reason and a danger marker for loopback (including its kernel
flag) or default-route changes. `Plan::to_json` emits version 1 and exact
operation arguments. Generating a plan is pure and does not apply changes;
`validate_plan(plan, snapshot, dangerous=false)` checks every step before a
write. Loopback names/kernel flags and IPv4/IPv6 default-route additions or
deletions are protected. It recomputes protection even if callers edit the
display marker. Explicit dangerous permits those resources; stale/missing
interface indices and invalid SDK specs still fail. The executor and CLI reuse
this check. Concurrent changes after observation remain possible.
The read-only `plan` and unconfirmed `apply` CLI reuse this validation.

`build_plan(snapshot, desired)` 依次排列路由删除、地址删除、MTU 准备、Link UP、地址添加、路由添加、Link DOWN。完整修改值用于进一步排序，因此输入顺序不影响计划。每步包含原因及回环接口（包括内核标志）、默认路由修改的危险标记。`Plan::to_json` 输出版本 1 和精确操作参数；生成计划是纯逻辑，不应用修改。`validate_plan(plan, snapshot, dangerous=false)` 在写入前检查每一步，保护回环名称、内核标志以及 IPv4/IPv6 默认路由增删。即使调用者编辑显示标记，也会重新计算保护。显式 dangerous 可放行这些资源，但过期或缺失索引、非法 SDK spec 仍失败。执行器、只读 `plan` 和未确认 `apply` CLI 复用该检查；观测后仍可能发生并发变化。
