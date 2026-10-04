# MoonNetlink 工程总纲与实施 TODO

> 文档状态：项目设计基线（Source of Truth）  
> 目标赛事：2026 年 10 月 MoonBit 黑客松，章程截止日期为 2026-10-24  
> 目标平台：Linux / MoonBit native  
> 暂定项目名：`MoonNetlink`  
> 暂定 CLI 名：`moonnet`

## 0. 如何使用这份文档

这不是一份只罗列功能名称的任务表，而是项目的工程总纲。接手实现的 agent 在修改代码前，应先完整阅读以下内容，理解项目为什么存在、各层的职责、MVP 边界和验收方式，再领取具体任务。

任务状态约定：

- `[ ]`：尚未开始；
- `[x]`：已经完成，并通过该任务列出的验收条件；
- 进行中的任务应在任务末尾写 `负责人 / 开始日期 / 当前阻塞`，不要仅通过勾选框表达；
- 如果设计发生变化，先修改本文件中的“架构决策”，说明原因和影响，再修改代码；
- “代码写完”不等于完成。对应测试、文档、示例和验证命令必须同时完成。

提交规则（用户要求）：**每完成一个可独立验收的小 TODO，必须创建一笔对应的真实
commit，然后再开始下一个 TODO。** 该提交应包含此任务的实现、相关测试、文档、
预期公共接口变化及本文件的状态更新。不能把多个已完成的小 TODO 攒成一个大提交，
也不能把同一任务的实现、测试和文档拆成数笔提交来凑数量。详细操作见第 19.1 节。

仓库已经进入 Phase 0：最小 MoonBit 模块、通用 codec 雏形、Linux transport 和 `inspect_links` 探针已经建立。继续实现时仍应先完成可行性闸门，而不是一次性创建全部抽象。

---

## 1. 项目一句话定义

MoonNetlink 是一个 **MoonBit 原生的 Linux RTNetlink SDK 与声明式网络状态工具**：它为 MoonBit 程序提供类型安全的网卡、地址、路由和邻居表查询/修改/监听能力，并提供 `snapshot -> diff -> plan -> apply` 的安全配置工作流。

它应当成为 MoonBit 生态中构建以下软件的基础设施，而不是一个只能完成单次演示的脚本：

- 容器网络与轻量 CNI 工具；
- Kubernetes 节点网络组件；
- VPN、代理和网关程序；
- Linux 网络监控与故障诊断工具；
- Network Namespace 网络实验和自动化测试；
- 声明式服务器网络配置工具。

## 2. 项目价值与生态定位

### 2.1 解决的具体缺口

截至项目立项调研时，MoonBit 包生态中没有发现可直接使用的 RTNetlink / `NETLINK_ROUTE` 库。MoonBit 程序若要管理 Linux 网络，通常只能：

1. 调用 `ip` 命令并解析文本或 JSON；
2. 为每个功能单独编写 C FFI；
3. 自己重复实现 Netlink 二进制协议、序列号、multipart 响应和错误处理。

这些方案分别带来外部进程依赖、脆弱的数据交换、重复劳动和难以复用的问题。Linux 上大量网络基础设施都建立在 Netlink 之上，因此这是一个较底层、通用性强、能够支持后续多个项目的生态缺口。

### 2.2 项目不是哪些东西

MoonNetlink **不是**：

- 只有几个 Linux 常量和 extern 声明的薄 FFI binding；
- 对 `ip` 命令的 shell 包装；
- 仅展示一次 `RTM_GETLINK` 的 demo；
- 试图在一个月内完整复刻 `iproute2`；
- 跨平台网络配置抽象。项目明确优先服务 Linux；
- 对所有 Netlink family 的一次性实现。首期只聚焦 `NETLINK_ROUTE`。

### 2.3 对标对象与差异化

可参考但不能机械翻译的成熟实现：

- Go：`vishvananda/netlink`；
- Rust：`rust-netlink/netlink-packet-route` 与 `rtnetlink`；
- Linux：`iproute2` 和内核 UAPI 头文件。

MoonNetlink 的差异化重点：

- 使用 MoonBit 类型系统表达 RTNetlink 对象和错误；
- 将纯协议编解码与 Linux I/O 分离，使核心层容易测试；
- 保留未知属性，面对新内核属性时能够前向兼容；
- 提供真实 Network Namespace E2E 与 `ip -j` 差分测试；
- 在基础 SDK 之上提供安全、可展示的声明式 `plan/apply` 能力；
- API、测试、文档和 CLI 都以 MoonBit 工程习惯重新设计。

## 3. 总体目标与成功定义

### 3.1 基础目标：成为一个真正可用的 MoonBit Linux 库

项目必须满足：

- MoonBit 是主要实现语言；
- C 代码只承担 MoonBit/async 暂时无法直接完成的最小系统调用边界；
- 能查询 Link、Address、Route、Neighbor；
- 能修改 Link 状态、Address、Route；
- 能监听 Link、Address、Route、Neighbor 变化事件；
- 所有来自内核的二进制数据都进行边界检查；
- 提供稳定的公共类型、错误类型和文档；
- 发布到 mooncakes.io，并包含 OSI 认可的许可证。

### 3.2 季度奖竞争目标：从协议库上升为基础设施项目

为了达到季度优秀项目的竞争水平，项目还应实现：

- 规范化网络快照；
- 声明式 Desired State；
- 可审查、确定性的 Diff 与 Plan；
- 默认 dry-run、安全确认与关键资源保护；
- 顺序执行、失败报告和尽力回滚；
- 幂等性：成功 apply 后再次 plan 应为空；
- 与 `ip -j` 的差分验证；
- 可复现的 Network Namespace / veth 端到端演示；
- 畸形数据、随机属性和截断输入的健壮性测试；
- 能被另一个真实示例项目使用，而不仅是自测。

### 3.3 赛事硬性验收要求

根据仓库中的赛事章程，最终交付至少包含：

- [ ] 公开 GitHub 仓库，历史清晰且不少于 10 个有效 commits；
- [ ] 完整源代码，目录和包边界清晰；
- [ ] README：目标、安装、使用、权限、示例、限制；
- [ ] CI 覆盖 check、build、test；
- [ ] 至少一个可运行示例；
- [ ] 核心路径的完整测试；
- [ ] mooncakes.io 发布包；
- [ ] OSI 认可的开源许可证；
- [ ] 参考项目、参考范围和许可证说明；
- [ ] 至少三个完整使用场景；
- [ ] 赛期内新增工作可验证，不用空提交或机械拆分凑 commits。

章程原文见：[MoonBit 黑客松大赛章程](./MoonBit%20黑客松大赛章程/MoonBit%20黑客松大赛章程.md)。

---

## 4. 预期使用场景

### 场景 A：容器网络初始化

容器运行时或实验性 CNI 工具调用 MoonNetlink：

1. 找到已经移动进 namespace 的 veth；
2. 将接口设为 UP；
3. 添加容器 IP 和前缀；
4. 添加默认路由；
5. 查询状态并验证结果。

价值：这是云原生基础设施中的真实需求，能够展示库的查询、修改和验证闭环。

### 场景 B：声明式服务器网络配置

运维工具读取 JSON desired state：

1. 获取当前快照；
2. 计算安全的变更计划；
3. 用户检查 dry-run 输出；
4. 显式确认后执行；
5. 输出逐步结果和回滚报告；
6. 再次运行时得到空计划。

价值：展示的不是若干独立 syscall，而是可以用于自动化的高层能力。

### 场景 C：实时网络变化监控

监控程序订阅 RTNetlink multicast groups，将网卡、地址、路由和邻居变化输出为 JSON Lines，供日志、告警或测试工具消费。

价值：展示 `async`、长期事件流、未知属性兼容和标准化事件模型。

### 场景 D：隔离的网络实验测试

测试工具创建 Network Namespace 和 veth，在不改变宿主机实际网络的前提下构造拓扑，通过 MoonNetlink 修改并用 `ip -j` 交叉验证。

价值：既是用户场景，也是项目工程质量的重要证据。

---

## 5. 范围和优先级

### 5.1 P0：必须完成的 SDK 能力

- Netlink header 和 attribute 的安全编解码；
- 多消息 datagram 和 multipart response；
- ACK、`NLMSG_ERROR`、`NLMSG_DONE`、sequence 校验；
- Link / Address / Route / Neighbor 查询；
- Link UP/DOWN、MTU 修改；
- Address add/delete；
- Route add/delete；
- 独立监控 socket 和事件流；
- CLI 的 show、watch、inspect/decode；
- 单元测试、fixtures、Linux namespace E2E；
- README、API 文档、CI、发布。

### 5.2 P1：季度奖竞争力功能

- Snapshot / DesiredState / Diff / Plan；
- dry-run 默认行为；
- apply 执行报告；
- best-effort rollback；
- 幂等性验证；
- `ip -j` 差分测试；
- 一个容器网络初始化示例；
- 性能和内存基线；
- 畸形输入与属性随机测试。

### 5.3 P2：有余力再做

- 创建/删除常见虚拟链路，例如 dummy、veth、bridge；
- route rule；
- 更丰富的 route multipath；
- 生成 HTML 拓扑或状态报告；
- 更细粒度的 extack 字段和错误定位；
- 供其他 MoonBit 项目使用的 mock transport。

### 5.4 2026 年 10 月明确不做

- 完整 traffic control / qdisc / class / filter；
- netfilter；
- XFRM / IPsec；
- nl80211 Wi-Fi 管理；
- ethtool generic netlink；
- WireGuard generic netlink；
- 所有虚拟链路种类；
- 完整复刻 `iproute2` 的命令语法；
- 跨平台 transport；
- 宣称网络变更具有真正原子事务语义；
- 全屏 TUI。优先把时间投入库、测试和可复现演示。

---

## 6. 总体架构

### 6.1 分层图

```text
┌────────────────────────────────────────────────────────────┐
│ CLI / examples                                             │
│ moonnet show | watch | snapshot | plan | apply | decode    │
└──────────────────────────────┬─────────────────────────────┘
                               │
                ┌──────────────▼──────────────┐
                │ reconcile                   │
                │ 执行计划、报告、尽力回滚     │
                └───────────┬──────────┬──────┘
                            │          │
                 ┌──────────▼───┐   ┌──▼────────────────────┐
                 │ state        │   │ transport             │
                 │ 快照/差分/计划│   │ async socket/client   │
                 └──────────┬───┘   │ monitor/request loop  │
                            │       └───────┬───────────────┘
                            │               │
                  ┌─────────▼───────────────▼──┐
                  │ route                       │
                  │ Link/Address/Route/Neighbor │
                  └─────────────┬──────────────┘
                                │
                  ┌─────────────▼──────────────┐
                  │ core                       │
                  │ Header/Attr/Codec/Error     │
                  └─────────────┬──────────────┘
                                │
                  ┌─────────────▼──────────────┐
                  │ 最小 Linux C shim           │
                  │ socket/bind/connect/options │
                  └────────────────────────────┘
```

依赖必须保持单向：

```text
route      -> core
transport  -> core + route + moonbitlang/async
state      -> route
reconcile  -> state + route + transport
CLI        -> 上述公共包
```

`core`、`route` 和 `state` 应尽可能保持纯 MoonBit、确定性和无系统权限依赖。只有 `transport` 与 Linux native/async 强绑定。

### 6.2 包职责

#### `core`

负责 Netlink 通用二进制协议，不知道 RTNetlink 中“网卡”或“路由”的业务含义：

- `NetlinkHeader`；
- `NetlinkMessage`；
- `NetlinkAttribute`；
- 4 字节对齐；
- 整数读写和边界检查；
- 多消息 datagram 解析；
- 通用 flags、控制消息和 codec error；
- 未知 attribute 的原始载荷保留。

#### `route`

负责 `NETLINK_ROUTE` 的类型化模型和 codec：

- `Link` / link attributes；
- `Address` / IP family / prefix；
- `Route` / table / gateway / output interface；
- `Neighbor` / MAC / NUD state；
- query、mutation 和 event 的消息构造/解析；
- 未知属性向上保留，而不是静默丢弃。

#### `transport`

负责 Linux socket 与异步请求生命周期：

- 打开、绑定、连接 `AF_NETLINK/NETLINK_ROUTE` socket；
- 把非阻塞 fd 包装成 `@raw_fd.RawFd`；
- `RouteClient`：序列化的 request/response；
- `RouteMonitor`：独立 multicast socket；
- sequence 分配、响应过滤、multipart 收集；
- timeout、关闭和系统错误映射；
- 不在 C 侧解析 Netlink 消息。

#### `state`

负责纯状态模型：

- 当前快照 `NetworkSnapshot`；
- 用户期望 `DesiredState`；
- 规范化、稳定排序和 JSON；
- 计算 `Diff`；
- 生成具有依赖顺序的 `Plan`；
- 本层不执行真实系统修改。

#### `reconcile`

负责把计划应用到 Linux：

- preflight 检查；
- 默认 dry-run；
- 显式确认；
- 按依赖顺序执行操作；
- 收集每一步结果；
- 失败后尽力执行补偿操作；
- 生成 `ApplyReport`；
- 重新抓取状态并验证幂等性。

#### `testkit`

负责测试和下游使用：

- 构造合法/非法二进制消息；
- fixture loader；
- fake transport 或录制回放；
- namespace 测试辅助；
- 不让 production API 为测试细节妥协。

### 6.3 公共类型所有权

遵循 MoonBit 包设计原则：用户需要构造、匹配或调用方法的公共具体类型，必须由对应的公共包拥有，不能藏在 `internal/*` 再勉强 re-export。

- `NetlinkHeader`、`NetlinkAttribute` 由 `core` 拥有；
- `Link`、`Address`、`Route`、`Neighbor` 由 `route` 拥有；
- `RouteClient`、`RouteMonitor` 由 `transport` 拥有；
- `NetworkSnapshot`、`DesiredState`、`Plan` 由 `state` 拥有；
- `ApplyReport` 由 `reconcile` 拥有；
- 根包可以用 `pub using` 提供常用入口，但不能模糊真实所有权。

---

## 7. 核心协议设计

### 7.1 Netlink message

Netlink header 固定包含：

- `length: u32`；
- `message_type: u16`；
- `flags: u16`；
- `sequence: u32`；
- `port_id: u32`。

实现要求：

- 不信任 `length`；
- header 小于 16 字节直接报错；
- `length < header_size` 报错；
- `length > remaining_bytes` 报截断错误；
- 每次循环必须前进，否则报错，禁止无限循环；
- 每条消息按 `NLMSG_ALIGN` 前进；
- 一个 datagram 中可能有多条消息；
- dump response 可能跨多个 datagram，以 `NLMSG_DONE` 结束；
- `NLMSG_ERROR` 中 error=0 表示 ACK，不应误判为失败；
- sequence 不匹配的消息不能混入当前请求结果。

### 7.2 Netlink attribute

attribute header 包含 `length: u16` 和 `type: u16`，payload 后按 4 字节对齐。实现要求：

- 解析 `NLA_F_NESTED`、`NLA_F_NET_BYTEORDER` 与基础 type mask；
- 同时提供类型化已知属性和 `UnknownAttribute`；
- 字符串必须处理结尾 NUL，但不能假设输入一定合法；
- MAC、IPv4、IPv6 和整数长度不正确时返回结构化错误；
- 未知属性保持原始 bytes，以支持未来内核版本和调试；
- 不在不可信输入路径使用 `try!`；
- 优先使用 `BytesView` 降低解析时复制，跨层持有时再转换为拥有型 `Bytes`。

### 7.3 RTNetlink 结构

首期覆盖以下 family message body：

- `ifinfomsg`：Link；
- `ifaddrmsg`：Address；
- `rtmsg`：Route；
- `ndmsg`：Neighbor。

每一类对象都应分别提供：

1. 内核消息 codec；
2. 领域模型；
3. 请求构造器；
4. 事件模型；
5. JSON/Debug 展示；
6. fixtures 与 malformed tests。

### 7.4 错误模型

错误至少分层为：

- `CodecError`：长度、对齐、字段、截断、未知但不可忽略的数据问题；
- `KernelError`：errno、原请求 header、可选 extack 信息；
- `TransportError`：open/bind/read/write/closed/timeout；
- `ProtocolError`：sequence mismatch、unexpected message、missing DONE 等；
- `PlanError`：desired state 冲突、依赖无法满足、受保护资源；
- `ApplyError`：执行失败并携带部分结果/回滚结果。

错误必须保留足够上下文用于 CLI 展示，不能全部压扁成字符串。

---

## 8. Transport 与 async 设计

### 8.1 最小 C shim

C 层的目标是“系统调用桥”，不是第二套业务实现。首个候选接口：

```moonbit
// 仅为方向草案；实现前必须通过 moon ide doc 和小型探针确认当前 FFI 语法。
extern "C" fn native_open_route_socket(groups : UInt) -> Int
  = "moonnetlink_open_route_socket"
```

C 函数负责：

1. `socket(AF_NETLINK, SOCK_RAW | SOCK_NONBLOCK | SOCK_CLOEXEC, NETLINK_ROUTE)`；
2. `bind(sockaddr_nl)`；
3. `connect` 到 kernel port id 0，使 MoonBit 可以按连接 fd 读写；
4. 尝试启用 `NETLINK_EXT_ACK`；
5. 尝试启用 `NETLINK_GET_STRICT_CHK`；
6. 返回 fd，失败时返回可映射的 `-errno`。

C 层不得：

- 持有 MoonBit 对象；
- 创建隐藏线程；
- 解析 Netlink 消息；
- 管理 pending request map；
- 吞掉 errno 或只返回模糊的 `-1`。

### 8.2 为什么使用 async

Netlink 查询和 multicast monitor 都会等待 fd 可读。`moonbitlang/async/raw_fd` 可以把非阻塞 fd 纳入 MoonBit 异步运行时，避免阻塞整个线程或自行维护 epoll 循环。

MoonBit async 约定：

- 使用 `async fn`，没有 `await` 关键字；
- async 函数默认可以 raise，不要机械添加 `raise`；
- 只有 `transport`、`reconcile` 和异步 CLI 入口需要 async；
- codec/state 单元测试保持同步、纯函数优先。

### 8.3 Client 与 Monitor 必须分 socket

MVP 不使用一个复杂后台 pump 同时处理请求和事件，而采用两个清晰对象：

- `RouteClient(groups=0)`：只发送请求并接收与 sequence 匹配的响应；
- `RouteMonitor(groups=...)`：只接收 multicast 事件。

`RouteClient` 首期通过 async `Mutex` 串行化请求：

1. 获取 request mutex；
2. 分配非零 sequence；
3. 编码并一次写入完整 datagram；
4. 循环读取 datagram；
5. 拆分其中的 message；
6. 验证 sequence / pid / message type；
7. 收集 multipart body；
8. 处理 ACK、kernel error 和 DONE；
9. 释放 mutex。

串行请求在首版是有意设计：它显著降低 pending map、并发响应分发和关闭竞态的复杂度。真实并发请求可在 API 稳定后演进。

### 8.4 必须先验证的 fd/datagram 问题

`RawFd::read` 的具体缓冲、取消和 datagram 截断行为必须通过当前版本文档和探针确认，不能凭印象实现。

- [x] 确认 `RawFd` 构造、read、write、close 的准确签名和所有权；
- [ ] 确认取消/超时后 fd 是否仍可安全复用；
- [x] 验证 connected Netlink socket 能否通过 RawFd 完整 write/read；
- [x] 验证一次 read 的 datagram 边界行为；
- [x] 选择安全的初始缓冲策略，并能识别可能的截断；
- [x] RawFd 无法报告 `MSG_TRUNC`：首版采用 256 KiB 可配置缓冲，读满即以 `DatagramMayBeTruncated` 安全失败；契约见 `docs/transport.md`；
- [x] 明确写入不完整时的错误行为：一次 write，不完整则 `ShortWrite`，绝不拆成多个 datagram。

---

## 9. RTNetlink 领域模型

### 9.1 Link

最低字段：

- index；
- name；
- kind；
- MTU；
- MAC；
- flags；
- operstate；
- master index；
- 未知属性。

操作：query all/by index/by name、set up/down、set MTU。

### 9.2 Address

自有 `IpAddress` 类型：

- IPv4：固定 4 字节或无损的 32-bit 表达；
- IPv6：固定 16 字节；
- 不用普通字符串作为内部真值；
- 字符串只用于输入输出，并必须严格解析。

最低字段：family、interface index/name、prefix length、scope、local/address、label、flags。

操作：query、add、delete。

### 9.3 Route

最低字段：family、destination/prefix、source、gateway、output interface、table、priority、protocol、scope、route type、flags。

操作：query、add、delete。

首期必须明确 route identity 和比较规则，避免同一条路由因默认字段差异被反复添加。

### 9.4 Neighbor

最低字段：family、interface、destination IP、link-layer address、NUD state、flags、neighbor type。

首期只要求 query 和 monitor；修改 Neighbor 为 P2，除非实现成本很低。

---

## 10. 声明式状态、计划与安全边界

### 10.1 Snapshot

`NetworkSnapshot` 是当前系统网络状态的规范化表示。要求：

- JSON 输出稳定；
- 数组使用明确 key 排序，不能依赖内核返回顺序；
- 同一状态多次 snapshot 应产生相同语义结果；
- 同时保留调试所需字段和用于 diff 的规范化字段；
- 清楚区分稳定身份与易变字段，例如 interface index 可能改变。

建议身份规则：

- Link：以 name 为 desired-state 主身份，以 index 作为当前快照引用；
- Address：`ifname + family + address + prefix`；
- Route：规范化后的 `family + table + destination/prefix + gateway + oif + priority`，具体字段以差分试验修正。

### 10.2 DesiredState

安全起见，首版使用显式资源意图：

- 每个资源带 `ensure: present | absent`；
- 未出现在 desired state 中的宿主机资源默认不删除；
- 首期不提供“配置文件即全机唯一真值”的 destructive authoritative mode；
- Link 修改只针对已经存在的 link，除非 P2 实现 link create；
- 输入冲突必须在生成 plan 前报错。

### 10.3 Plan

计划操作候选：

- `SetLinkUp` / `SetLinkDown`；
- `SetMtu`；
- `AddAddress` / `DeleteAddress`；
- `AddRoute` / `DeleteRoute`。

顺序原则：

```text
创建/准备 link（未来） -> Link UP -> 添加地址 -> 添加路由
删除路由 -> 删除地址 -> Link DOWN/删除 link（未来）
```

Plan 必须：

- 确定性排序；
- 显示操作原因；
- 标记危险操作；
- 在执行前完成依赖和资源存在性检查；
- 可序列化，方便审查和测试；
- 在同样 current + desired 下得到同样结果。

### 10.4 Apply 与回滚

不能宣称 Netlink 多步配置是原子事务。项目术语统一为：

> ordered reconcile + best-effort rollback + detailed report

`ApplyReport` 至少包含：

- planned operations；
- completed operations；
- failed operation 和 kernel error；
- rollback attempted；
- rollback completed；
- rollback failed；
- final verification result。

安全策略：

- `plan` 和 `apply` 默认只展示 dry-run；
- 真正修改必须显式 `--yes`；
- 默认保护 loopback；
- 默认拒绝删除当前默认路由；
- 默认拒绝修改承载当前管理连接的接口（若无法可靠识别，至少清晰警告）；
- 只有显式 `--dangerous` 才允许绕过保护；
- 示例和 E2E 一律优先在临时 Network Namespace 中运行；
- 每次 apply 后重新 snapshot，验证目标和幂等性。

---

## 11. CLI 与用户体验

计划命令：

```text
moonnet link show [--json]
moonnet address show [--json]
moonnet route show [--json]
moonnet neighbor show [--json]
moonnet watch [link|address|route|neighbor|all] [--jsonl]
moonnet snapshot [-o current.json]
moonnet plan desired.json [--json]
moonnet apply desired.json [--yes] [--dangerous]
moonnet inspect --raw
moonnet decode fixture.bin
```

CLI 原则：

- 库优先，CLI 只组合公共 API，不复制协议逻辑；
- 默认输出适合人读，`--json` / `--jsonl` 适合工具消费；
- 权限不足、内核拒绝和 codec 错误使用不同退出信息；
- dry-run 输出必须足以让用户判断会改什么；
- `decode` 能离线解析 fixtures，方便在非 Linux 环境调试纯 codec；
- 不把 UI 美化置于协议正确性和测试之前。

---

## 12. 建议仓库布局

```text
moonnetlink/
├── moon.mod
├── moon.pkg                    # 可选 facade
├── README.mbt.md               # 可测试示例文档
├── README.md                   # 链接或同步入口
├── LICENSE
├── CHANGELOG.md
├── TODO.md
├── core/
│   ├── moon.pkg
│   ├── header.mbt
│   ├── attribute.mbt
│   ├── codec.mbt
│   ├── error.mbt
│   └── *_test.mbt
├── route/
│   ├── moon.pkg
│   ├── link.mbt
│   ├── address.mbt
│   ├── route.mbt
│   ├── neighbor.mbt
│   ├── event.mbt
│   └── *_test.mbt
├── transport/
│   ├── moon.pkg
│   ├── client.mbt
│   ├── monitor.mbt
│   ├── ffi.mbt
│   ├── netlink_linux.c
│   └── *_test.mbt
├── state/
│   ├── moon.pkg
│   ├── snapshot.mbt
│   ├── desired.mbt
│   ├── diff.mbt
│   ├── plan.mbt
│   └── *_test.mbt
├── reconcile/
│   ├── moon.pkg
│   ├── apply.mbt
│   ├── rollback.mbt
│   ├── report.mbt
│   └── *_test.mbt
├── testkit/
│   ├── moon.pkg
│   ├── builders.mbt
│   └── fake_transport.mbt
├── cmd/moonnet/
│   ├── moon.pkg
│   └── main.mbt
├── examples/
│   ├── inspect_links/
│   ├── watch_routes/
│   └── container_network/
├── fixtures/
│   ├── raw/
│   └── expected/
├── docs/
│   ├── architecture.md
│   ├── protocol-notes.md
│   ├── safety.md
│   ├── comparison.md
│   └── decisions/
├── scripts/
│   └── integration-netns.sh
└── .github/workflows/
    └── ci.yml
```

这是目标形态，不要求第一天创建所有空目录。包应在出现真实职责和代码时建立，禁止用大量空壳文件制造进度。

---

## 13. 测试与质量策略

### 13.1 纯 codec 单元测试

`core` 和 `route` 的大部分测试应当无需 root、无需 Linux socket：

- header 正常/边界/截断；
- attribute 正常/嵌套/未知/错误长度；
- 多消息 datagram；
- alignment 和 padding；
- ACK / error / DONE；
- Link/Address/Route/Neighbor fixtures；
- encode/decode roundtrip；
- parser 遇到任意输入都必须“前进或返回错误”。

关键性质：

```text
decode(encode(valid_value)) == normalize(valid_value)
```

对于内核原始 fixture，则验证：

```text
encode(decode(raw)) 在语义上等价，而不强求未知 padding 字节完全一致
```

### 13.2 Fixture 测试

fixtures 必须记录来源：

- 自己在隔离 namespace 中抓取；
- 使用何种 kernel/iproute2；
- 对应命令和预期 JSON；
- 不包含隐私地址、主机名或其他敏感信息。

每个领域对象至少包含：

- 普通成功消息；
- 多个 attributes；
- 未知 attribute；
- 截断消息；
- 错误长度；
- family/字段边界。

### 13.3 `ip -j` 差分测试

在同一个 namespace 中分别读取：

```text
ip -j link
ip -j address
ip -j route
ip -j neighbor
```

将 `ip` 输出与 MoonNetlink 的规范化结果比较。只比较双方都明确定义的字段，差异必须可解释并记录，不能为了“测试通过”随意忽略字段。

### 13.4 Network Namespace E2E

E2E 流程：

1. 创建唯一名称的临时 namespace；
2. 创建 veth pair；
3. 一端放入 namespace；
4. 用 MoonNetlink 设置 UP、地址和路由；
5. 用 MoonNetlink query 验证；
6. 用 `ip -j` 差分验证；
7. 启动 monitor 并制造 link/address/route 事件；
8. 验证收到类型化事件；
9. 无论成功失败都清理 namespace。

测试绝不能直接修改宿主机默认网络。

### 13.5 健壮性测试

- 随机 attribute 顺序；
- 未知 attribute type；
- 0、1、2、3 字节结尾截断；
- 伪造巨大 length；
- 嵌套深度限制；
- 重复 attribute；
- 一个 datagram 多条不同类型消息；
- sequence mismatch；
- multipart 缺少 DONE；
- kernel error 携带或不携带 extack。

目标不是追求一个好看的测试数量，而是覆盖协议不变量和失败路径。季度奖目标可把 100+ 有意义测试作为结果指标，但不能机械拆分测试凑数。

### 13.6 MoonBit 工程验证顺序

每个实现切片至少运行：

```text
moon check --target native --warn-list +73
moon test --target native
moon fmt
moon info --target native
```

纯 MoonBit 包还应尽量运行：

```text
moon check --target all
moon test core
moon test route
moon test state
```

`pkg.generated.mbti` 只能通过 `moon info` 生成，不能手工编辑。公共 API 改动必须审查生成的 interface diff。

---

## 14. 分阶段实施计划

### Phase 0：立项与可行性闸门（2026-10-02 ～ 2026-10-04）

当前状态：2026-10-02 已在 WSL2 Linux 6.6 上完成首次真实 `RTM_GETLINK`，MoonBit/async 成功解码出 `lo` 与 `eth0`。仍需解决 datagram 截断策略并确认发布元数据后，才算完整通过闸门。

目标：用最少代码验证最危险的技术假设。只有通过本阶段，才展开完整架构。

- [ ] 确认最终 GitHub/Mooncakes 包名和许可证（当前暂定 `eisem/moonnetlink` + MIT）；
- [x] 初始化最小 MoonBit native 模块；
- [x] 使用 `moon ide doc` 确认当前 async、RawFd、Bytes 和 FFI API；
- [x] 编写最小 C shim 创建 connected nonblocking Netlink socket；
- [x] 手工编码 `RTM_GETLINK` dump 请求；
- [x] 通过 `RawFd` 写入请求并读取响应；
- [x] 解析 header，找到 loopback `lo`；
- [x] 输出 message type、interface index/name/flags，并验证请求 sequence；
- [x] 在 `docs/transport.md` 记录 datagram 读取、缓冲、所有权和关闭语义；
- [x] 将探针保留在 `examples/inspect_links`，而不是丢弃。

已验证命令：

```text
moon check --target native
moon test --target native
moon run --target native examples/inspect_links
```

首次结果：4 个单元测试通过，真实 dump 输出 `link index=1 name=lo` 与 `link index=2 name=eth0`。

退出条件：

```text
在 Linux 上执行一个 MoonBit native 程序，直接通过 AF_NETLINK 获取并打印 lo；
过程中不调用 ip 命令完成实际查询；
错误路径不会 hang；
已确认 RawFd 的基本读写与关闭行为。
```

如果闸门失败：先收敛 C shim 或 transport 方案，不要继续堆领域模型。

### Phase 1：通用 codec（2026-10-05 ～ 2026-10-08）

状态：2026-10-03 提前完成；codec、控制消息、真实 multipart fixture、测试与接口审查均已通过。

- [x] 建立 `core` 包；
- [x] 实现 host/Linux ABI 整数读写辅助；
- [x] 实现 `NLMSG_ALIGN` / `NLA_ALIGN`；
- [x] 实现 header encode/decode；
- [x] 实现 attribute encode/decode；
- [x] 实现 datagram 多消息解析；
- [x] 实现 ACK/error/DONE 控制消息；
- [x] 定义结构化 `CodecError`；
- [x] 保留未知属性；
- [x] 增加合法、截断、错误长度和 roundtrip 测试；
- [x] 收集第一批真实 fixtures；
- [x] 生成并审查 `core/pkg.generated.mbti`。

2026-10-03 codec/Link/Address/Route 纵向切片验证：Windows native 运行 35 个测试全部通过；
WSL2/Linux native 运行 36 个测试全部通过（包含真实 Netlink 截断测试），随后只读执行
`examples/inspect_links`，成功得到 `lo` 与 `eth0`。验证命令：

```text
moon check --target native --warn-list +73
moon test --target native
moon info
moon run --target native examples/inspect_links
```

2026-10-03 从 Linux 6.6.87.2-microsoft-standard-WSL2 直接通过 `AF_NETLINK`
抓取 `RTM_GETLINK` 响应，固化了去标识化的 `lo` 数据消息及同类 dump 的真实
`NLMSG_DONE`。fixture 不包含主机地址、主机名或非 loopback MAC，并覆盖类型化 Link 解码、
multipart 完成消息和语义 roundtrip。

本切片明确未包含 extack attribute 解码和通用请求超时；这些任务分别留在 Phase 3 和
`RouteClient` 阶段。

退出条件：

- 无 socket 也能完整运行 codec tests；
- 所有 parser 对畸形输入只会返回结果或结构化错误，不 panic、不死循环；
- 至少覆盖一个 multipart dump fixture。

### Phase 2：类型化 RTNetlink 查询（2026-10-09 ～ 2026-10-13）

- [x] 建立 `route` 包及 Link/Address 公共类型；
- [x] Link query all/by index/by name + decode（index/name/kind/MTU/MAC/flags/operstate/master/未知属性）；
- [x] Address query + decode（接口名需由后续 `RouteClient` 与 Link 数据关联）；
- [x] Route query + decode（接口名需由后续 `RouteClient` 与 Link 数据关联）；
- [x] Neighbor query + decode；
- [x] 实现严格 IP/MAC parser 与 formatter；
- [x] 建立 `transport.RouteClient`；
- [x] mutex 串行 request；
- [x] sequence、multipart、ACK、timeout；
- [x] CLI `link/address/route/neighbor show`；
- [x] JSON 输出与稳定排序；
- [x] 与 `ip -j` 做第一次差分；
- [x] 每类对象添加 fixtures 和黑盒测试。

2026-10-03 Phase 2 进展：Link 已支持 all/by-index/by-name 查询并严格校验名称；Address
已支持全 family dump、IPv4/IPv6 固定宽度解码、label/flags/未知属性；Route 已支持全
family/table dump、前缀、gateway、接口、table/priority 和未知属性；Neighbor 已支持全 family
dump、目标 IP、MAC、NUD state、flags/type/probes 与未知属性。严格文本层覆盖 IPv4、IPv6
（含 `::` 和尾部嵌入 IPv4）及六字节 MAC，并提供规范化 formatter。真实 Linux 只读示例
`examples/inspect_links`、`examples/inspect_addresses`、`examples/inspect_routes` 与
`examples/inspect_neighbors` 均通过。`RouteClient` 已拥有单一 socket、自动分配非零 sequence，
以 async mutex 串行查询/关闭，并在同一临界区内为 Address/Neighbor 关联接口名。timeout 与
取消后的 socket 复用已通过真实 Linux 测试：sequence 不匹配的请求超时后，同一 fd 可立即
完成新 dump；multipart 持续收集到 DONE，ACK 不会提前结束。`cmd/moonnet` 已提供四类
`show [--json]`，人类输出和 JSON 均按类型化键稳定排序，缺失字段输出 `null`。

2026-10-04 已完成审查发现的四类修复：`RouteClient::get_link_by_index` /
`get_link_by_name` 使用单条响应路径，收到匹配的 `RTM_NEWLINK` 即完成，不等待 DONE；
输入错误、内核拒绝及后续 socket 复用均有真实 Linux 测试。Link 根据 `ifi_type`
区分 Ethernet/loopback 的六字节 MAC 与其他硬件地址；IPIP、InfiniBand 等
`IFLA_ADDRESS` 保留在未知属性中，避免一个合法非 Ethernet 接口使整个 dump 失败。
multipart 状态机跨 datagram 记录 `NLM_F_DUMP_INTR`，读取到 DONE 后返回
`TransportError::DumpInterrupted`，不返回部分状态，也不自动重试；中断发生在 body 或
DONE 的失败路径均有 fixture 测试。Route 排序补齐源前缀长度和 preferred source，
通过逐个改变输出字段、反转输入顺序的回归测试。

本轮验证：Windows native 62/62、WSL2/Linux native 67/67 测试通过。
新增 `.ci/validate-queries.sh` 在自动销毁的 user/network namespace 中创建 IPIP/veth，
执行 6 个真实 transport 测试、四类 CLI 查询及 `ip -j` 差分；同时保留原有只读差分与
隔离 Link DOWN/UP 验证。差分明确区分 MAC 与非 Ethernet 地址，并规范化 operstate 拼写。
公共接口新增两个类型化点查方法、低层 `request_single` 和 `DumpInterrupted`；
Link 的公共字段保持兼容。验证命令：

```text
moon check --target native --warn-list +73
moon test --target native
moon fmt
moon info --target native
bash .ci/validate-queries.sh
python3 .ci/diff_ip_json.py
bash .ci/validate-link-state.sh
```

退出条件：

- 在普通 Linux 主机和测试 namespace 中能列出四类对象；
- 与 `ip -j` 的核心字段一致；
- 公共 API 不泄漏 C 指针或内部解析类型。

### Phase 3：修改与事件监听（2026-10-14 ～ 2026-10-17）

- [x] Link UP/DOWN；
- [x] Link MTU；
- [x] Address add/delete；
- [x] Route add/delete；
- [x] 明确 add 的 create/exclusive/replace flags；
- [x] 解析 kernel errno 和 extack；
- [x] 建立独立 `RouteMonitor`；
- [x] 订阅 Link/Address/Route/Neighbor groups；
- [x] 类型化事件；
- [x] CLI `watch --jsonl`；
- [x] namespace E2E；
- [x] 监控事件 E2E；
- [x] 所有 mutation 先在隔离 namespace 验证。

2026-10-04 完成 Phase 3 纵向切片。`route` 新增纯编码的 `AddressSpec`、
`RouteSpec`、`AddMode` 和 `MutationError`；`transport.RouteClient` 新增 MTU、
IPv4/IPv6 地址与 unicast 路由增删方法，全部复用 mutex、sequence、ACK 与 timeout。
add 默认 `Exclusive`（0x0605），显式 `Replace`（0x0505）；拒绝非法接口、前缀、
目的地址 host bits、table 和 gateway family，未知属性仍保留。当前修改子集不包含
peer address、multipath、rule、source-specific route 或 onlink flags。

`core.ExtendedAck` 解析 capped/uncapped `NLMSG_ERROR`、成功 ACK 警告和 DONE
诊断，保留文本、offset、cookie、missing fields 与未知 TLV。内核拒绝保留正数
errno；有 TLV 时返回 `KernelRejectedDetailed`，含原请求 header（DONE 时为 None）
和结构化诊断。畸形长度、回显请求越界、UTF-8/NUL 和整数长度都有失败测试。

独立 `RouteMonitor` 默认订阅 Link、Neighbor、IPv4/IPv6 Address/Route，输出类型化
NEW/DEL 事件，按收到顺序保留批量 datagram；整包校验后才入队。ENOBUFS/OVERRUN
显式报告 `EventStreamLost`，读满缓冲及 codec 错误均不被吞掉。取消后可再次读取；
关闭会主动取消 pending read 并释放 fd，避免仅关闭 RawFd 不能唤醒等待任务的问题。
`watch [filter] --jsonl` 逐行立即输出 `{event, object}`，订阅完成在 stderr 发出
ready 信号；Address/Neighbor 事件保留 ifindex，interface_name 为 null。

`.ci/validate-mutations.sh` 在自动销毁的 `unshare -Urn` 中创建 veth，由
`examples/configure_veth` 配置 MTU 1400、UP、IPv4/IPv6 地址和 table 1000 路由，
验证重复 exclusive 添加返回 EEXIST、replace 改变网关、删除恢复 MTU 1500/DOWN。
并行 all/neighbor 两个 monitor 验证四类对象、IPv4/IPv6 新增删除与过滤；直接
`ip -j` 验证及四类 dump 差分均通过。无效网关实际返回 errno 101 和
`Nexthop has invalid gateway` extack；失败后同一 client 仍可查询。测试进程在
finally 中按进程组终止，namespace 不触及宿主接口。此处验证平台为 WSL2 Linux
6.6.87.2；SDK mutation 直接执行，Phase 4 的默认 dry-run 与关键资源保护仍未实现。

最终验证：Windows native 75/75、Linux native 82/82，隔离 live transport 8/8；
公共 `.mbti` 已由 `moon info` 更新并审查，文档和 README 同步。命令：

```text
moon check --target native --warn-list +73
moon test --target native
moon fmt --check
moon info --target native
bash .ci/validate-queries.sh
bash .ci/validate-link-state.sh
bash .ci/validate-mutations.sh
git diff --check
```

退出条件：

- 可以从零配置一端 veth 的 UP、IP 和路由；
- `ip -j` 验证一致；
- monitor 能观察到测试制造的变化；
- 失败时能显示可理解的 kernel error。

### Phase 4：声明式状态引擎（2026-10-18 ～ 2026-10-20）

P4-01 已完成（2026-10-04）：纯 `state.NetworkSnapshot` 保存四类完整对象，复制输入
及 unknown attribute 数组，以名称查询 Link、以 ifindex 关联名称；保留未知 bytes。
`state/snapshot_test.mbt` 验证输入清空后状态仍完整、缺失引用返回 None。
验收命令：`moon check --target native --warn-list +73`、`moon test --target native state`、
`moon fmt`、`moon info --target native`；文档见 `docs/state.md`。采集非原子，JSON 和
计划能力仍由后续独立 TODO 完成。

- [x] `NetworkSnapshot`；
- [ ] 规范化与确定性 JSON；
- [ ] `DesiredState` schema 和严格校验；
- [ ] present/absent 语义；
- [ ] `Diff`；
- [ ] `Plan` 和依赖排序；
- [ ] loopback/default-route 保护；
- [ ] dry-run CLI；
- [ ] `ApplyReport`；
- [ ] best-effort rollback；
- [ ] apply 后重新验证；
- [ ] 幂等性 E2E：第二次 plan 为空；
- [ ] 冲突 desired state 和中途失败测试。

退出条件：

- 一个 JSON desired state 能在临时 namespace 中完成 plan/apply；
- 第一次 apply 达成目标；
- 第二次 plan 为空；
- 人为制造失败时报告已完成、失败及回滚步骤。

### Phase 5：展示、性能与下游场景（2026-10-21 ～ 2026-10-22）

- [ ] 容器网络初始化完整示例；
- [ ] snapshot/plan/apply 演示；
- [ ] monitor 演示；
- [ ] 与 shelling out to `ip -j` 的延迟/开销基线；
- [ ] 大量 route/neighbor fixture 的解析基线；
- [ ] 检查不必要分配和 Bytes 拷贝；
- [ ] 输出 demo 脚本或录屏所需步骤；
- [ ] 写清楚“为什么这不是一个薄 binding”。

退出条件：三个主要场景均可由新用户按 README 在隔离环境复现。

### Phase 6：发布与赛事验收（2026-10-23 ～ 2026-10-24）

- [ ] README.mbt.md 的公共示例可测试；
- [ ] 安装、权限、Linux 版本/架构要求；
- [ ] architecture / protocol / safety 文档；
- [ ] 参考来源和许可证清单；
- [ ] API docs 和 `pkg.generated.mbti`；
- [ ] GitHub Actions：check/build/test；
- [ ] 隔离的 privileged integration job；
- [ ] release 构建；
- [ ] mooncakes.io 发布；
- [ ] GitHub release 和 changelog；
- [ ] 从干净环境按 README 完整复现；
- [ ] 检查有效 commit 数和开发记录；
- [ ] 准备季度评选说明：生态价值、工程难点、验证证据、后续路线。

退出条件：满足章程全部验收条款，不依赖作者机器上的隐含配置。

---

## 15. 关键 API 草案（方向性，不是最终签名）

以下只用于说明公共能力边界。实现 agent 必须先用 `moon ide doc` 确认当前 MoonBit/依赖 API，并在 `moon info` 中审查最终签名。

```moonbit
// route package
pub async fn get_links(client : RouteClient) -> Array[Link]
pub async fn get_addresses(client : RouteClient) -> Array[Address]
pub async fn get_routes(client : RouteClient) -> Array[Route]
pub async fn get_neighbors(client : RouteClient) -> Array[Neighbor]

// state package: pure functions
pub fn normalize(snapshot : NetworkSnapshot) -> NetworkSnapshot
pub fn diff(current : NetworkSnapshot, desired : DesiredState) -> Diff
pub fn build_plan(diff : Diff) -> Plan

// reconcile package
pub async fn apply(
  client : RouteClient,
  plan : Plan,
  dry_run? : Bool = true,
  dangerous? : Bool = false,
) -> ApplyReport
```

API 设计要求：

- 优先 labeled/optional parameters；
- 公共方法有 docstring 和可测试示例；
- 错误不压缩为字符串；
- 不将 Linux C struct 内存布局直接暴露为用户 API；
- 不为未来所有 family 预先设计庞大泛型框架；
- 首先让 RTNetlink API 清晰可用，再考虑抽象复用。

---

## 16. CI 设计

建议拆为三层：

### Job A：portable pure checks

- `moon check --target all`（对支持所有后端的包）；
- codec/state tests；
- `moon fmt --check` 或等价检查；
- README 中 `mbt check` 示例。

### Job B：Linux native

- native build；
- native unit/integration tests；
- 最小真实 Netlink query；
- 无 root 的 dump/query 路径。

### Job C：privileged namespace E2E

- 只在受控 Linux runner/container 中执行；
- 检查 `CAP_NET_ADMIN`、`ip` 和 namespace 支持；
- 创建唯一 namespace；
- 执行 mutation、monitor、diff、apply、idempotency；
- `finally/trap` 清理；
- 失败时输出诊断但不泄漏 runner 网络信息。

---

## 17. 风险清单与应对

| 风险 | 影响 | 应对 |
|---|---|---|
| RawFd 不暴露 `MSG_TRUNC` | 固定缓冲过小时内核会丢弃 datagram 尾部 | 默认 256 KiB 可配置缓冲；读满即 `DatagramMayBeTruncated`，不解析；契约见 `docs/transport.md` |
| multipart/sequence 处理错误 | 查询混入事件或提前结束 | client/monitor 分 socket；fixture + E2E |
| 内核版本属性差异 | 新系统解析失败 | 保留 unknown attributes；严格已知字段长度，宽容未知字段 |
| mutation 误伤宿主网络 | 高风险 | 默认 dry-run、namespace、关键资源保护、显式 `--yes` |
| 范围过大导致无法交付 | 无法达到验收质量 | P0 优先；P2 不抢占测试和文档时间 |
| 公共 API 过早固化 | 后续难维护 | Phase 0/1 先验证；`moon info` 审查；0.x 版本说明稳定性 |
| 大量 FFI 降低 MoonBit 贡献度 | 评审价值下降 | C 只做 socket 边界，codec/model/state/reconcile 全部 MoonBit |
| `ip -j` 字段语义不完全对应 | 差分测试假失败 | 定义规范化层，只比较明确映射字段并记录差异 |
| root/CI 权限不可用 | E2E 无法跑 | unit fixture 为主；privileged job 单独隔离并提供本地脚本 |
| 只做展示、缺少下游价值 | 难竞争季度奖 | 完成 SDK + 声明式层 + 容器网络示例 |

---

## 18. 演示脚本目标

最终评审演示应控制在几分钟内，展示完整闭环：

1. 创建隔离 namespace 和 veth；
2. `moonnet snapshot` 展示初始状态；
3. 打开 `moonnet watch --jsonl`；
4. 对 desired JSON 执行 `moonnet plan`；
5. 展示将执行的 Link/IP/Route 操作和保护信息；
6. `moonnet apply ... --yes`；
7. watch 窗口实时出现事件；
8. `ip -j` 与 MoonNetlink query 交叉验证；
9. 再次 plan，输出空计划；
10. 展示一条畸形 fixture 被结构化拒绝，而不是 crash；
11. 自动清理 namespace。

这段演示同时证明：协议库、异步 transport、修改能力、事件、状态引擎、安全性和工程测试都真实存在。

---

## 19. Agent 协作规则

后续 agent 开始工程实现时必须遵守：

1. **先读全貌**：先读本文件，再读相关 package 和 generated interface；
2. **一次完成一个纵向切片**：实现 + 测试 + 文档一起交付，避免只创建类型空壳；
3. **先发现 API**：对 MoonBit、async、FFI 等现有能力先运行 `moon ide doc`，不要猜函数签名；
4. **保持依赖单向**：不得为了方便让 `core` 依赖 `route/transport`；
5. **保持 C shim 最小**：业务 codec 和模型必须在 MoonBit 中；
6. **不信任内核数据**：所有 length/index/slice 都做检查，不对输入使用 `try!`；
7. **不直接碰宿主网络**：mutation 和 destructive test 默认只在临时 namespace；
8. **不隐藏失败**：错误必须保留层次和上下文，测试不得通过 catch-all 吞错；
9. **公共 API 可审查**：每次公共变化运行 `moon info` 并检查 `.mbti`；
10. **一个小 TODO 一笔真实 commit**：每个可独立验收的小 TODO 完成后立即提交，实现、测试、文档和 API 一起交付；不攒大提交、不空提交、不机械拆分；细则见 19.1；
11. **不擅自扩大范围**：P2 工作必须在 P0/P1 质量达标之后；
12. **更新本 TODO**：任务完成时勾选、写验证命令和关键结果，并把状态更新纳入该任务的 commit；若有架构变化，同时更新相关章节；
13. **保留用户改动**：不要覆盖其他 agent 或用户未提交的工作；
14. **报告风险**：发现阻塞时说明复现方法、已有证据和建议选择，不只写“做不了”。

单个任务的交付说明模板：

```text
任务：
实现范围：
明确未做：
公共 API 变化：
测试/验证命令：
测试结果：
已知风险：
下一依赖任务：
```

### 19.1 每个小 TODO 的提交流程

1. 开始前明确任务边界、依赖、公共 API 和验收条件；过大的条目先在本文件拆成能独立
   验收的子任务。已有明确验收边界的条目无需为了数量继续拆分。
2. 完成该任务的实现、成功及失败路径测试、必要示例、文档和生成接口。纯声明或空壳
   类型不能单独算作完成的功能任务。
3. 执行与改动相关的检查；通过后更新该 TODO 的勾选、验证命令和结果。尚未完成的
   依赖或退出条件仍保留未勾选状态。
4. 明确暂存该任务的文件，审查 `git diff --cached` 和 `git diff --cached --check`，
   排除构建产物、依赖缓存与本地资料。提交边界见 `docs/repository.md`。
5. 为这个小 TODO 创建**一笔**可说明实际结果的 commit。提交信息应说明发生的行为
   变化；推荐格式为 `feat(state): add normalized network snapshots [P4-01]`。
6. 确认这笔提交已产生后，再进入下一个小 TODO。后续修复若确实改变行为或补齐遗漏
   可以单独提交，但不能为了数量制造错误、空提交或纯改提交信息。
7. 用户要求发布时推送并核对远程 hash；已经推送的真实历史保留，不重写历史、不把
   原有大提交重新切碎，不使用强制推送凑数量。

Phase 4 逐项提交边界如下；每行对应上方 Phase 4 的一个小 TODO，不能跨行合并成大
提交。实现与测试/文档属于同一行的完整交付。

| 编号 | 小 TODO / 单笔提交的交付内容 | 主要验收 |
| --- | --- | --- |
| P4-01 | `NetworkSnapshot`，稳定身份与 owned 状态模型 | 纯状态测试、保留原始对象、单向依赖 |
| P4-02 | 规范化、确定性 JSON 与只读 snapshot 入口 | 反转输入仍输出一致；Linux 实际采集 |
| P4-03 | `DesiredState` schema 和严格输入校验 | 未知字段、范围、接口名、IP/prefix、冲突失败 |
| P4-04 | present/absent 语义 | 仅处理显式资源；未声明资源不删除；不支持的意图明确拒绝 |
| P4-05 | `Diff` | 已满足意图为空差分；IPv4/IPv6 和默认路由身份规范化 |
| P4-06 | `Plan` 和依赖排序 | 确定性顺序、原因，添加/删除依赖测试 |
| P4-07 | loopback/default-route 保护 | 默认拒绝受保护修改；显式 dangerous 放行测试 |
| P4-08 | dry-run CLI | 严格读取配置、可审查输出、实际网络不变化 |
| P4-09 | `ApplyReport` | 逐步成功/失败及部分完成报告 |
| P4-10 | best-effort rollback | 倒序补偿、回滚失败保留，无原子事务宣传 |
| P4-11 | apply 后重新验证 | 查询实际状态，报告未达成目标，不只看 ACK |
| P4-12 | 幂等性 E2E | 隔离 namespace 第一次 apply 后第二次 plan 为空 |
| P4-13 | 冲突输入和中途失败集成测试 | 拒绝冲突；记录已完成、失败及回滚结果 |

仓库总提交数要求为至少 11 笔。本轮起点为 4 笔已推送提交；通过完成真实 TODO
增加提交数。数量达标不等于 Phase 4 或整个项目完成，未通过验收的条目不得勾选。

---

## 20. 项目级 Definition of Done

只有同时达到以下条件，项目才算完成：

- [ ] P0 全部完成；
- [ ] P1 的 Snapshot/Diff/Plan/Apply/幂等性完成；
- [ ] 三个主要场景可复现；
- [ ] 核心协议的成功与失败路径都有测试；
- [ ] namespace E2E 不修改宿主默认网络且能稳定清理；
- [ ] 与 `ip -j` 的差分结果有记录；
- [ ] 所有公共 API 有文档，示例可运行；
- [ ] `moon check`、`moon test`、`moon fmt`、`moon info` 通过；
- [ ] CI 从干净环境通过；
- [ ] mooncakes.io 包可安装；
- [ ] GitHub release 可下载/构建；
- [ ] README 明确 Linux/native/权限限制；
- [ ] 参考来源与许可证合规；
- [ ] 没有用“原子事务”“完整 iproute2 替代”等不准确宣传；
- [ ] 一个未参与开发的人能按 README 完成演示。

---

## 21. 后续版本路线（不属于 10 月验收承诺）

- `0.2`：Link create/delete，优先 dummy/veth/bridge；
- `0.3`：route rule 和 multipath；
- `0.4`：traffic control 子集；
- `0.5`：generic netlink core，支持 ethtool/WireGuard 等独立包；
- 长期：真实 CNI helper、网络拓扑诊断、更多下游 MoonBit 项目接入。

后续路线的存在是为了说明项目可持续演进，不得以此稀释 10 月 P0/P1 的完成质量。

---

## 22. 参考资料

- Linux rtnetlink manual：<https://man7.org/linux/man-pages/man7/rtnetlink.7.html>
- Linux kernel Netlink userspace API：<https://docs.kernel.org/userspace-api/netlink/index.html>
- Linux UAPI headers：`include/uapi/linux/netlink.h`、`rtnetlink.h`、`if_link.h`、`if_addr.h`、`neighbour.h`
- Rust netlink ecosystem：<https://github.com/rust-netlink>
- Go netlink：<https://github.com/vishvananda/netlink>
- iproute2：<https://git.kernel.org/pub/scm/network/iproute2/iproute2.git/>

参考代码时必须记录参考范围和许可证。原则、常量和协议格式应优先以 Linux 官方 UAPI 与文档为准；其他语言库用于理解成熟 API 和工程处理方式，不应机械逐行翻译。
