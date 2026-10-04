# MoonNetlink 项目申报书

## 基本信息

项目名称：**MoonNetlink：MoonBit 原生 Linux RTNetlink SDK 与声明式网络状态工具**

参赛者：**待填写**

联系方式：**待填写**

GitHub 仓库链接：[Eisem/moon_netlink](https://github.com/Eisem/moon_netlink.git)

项目方向：**MoonBit 系统编程基础库 / Linux 网络管理与云原生基础设施**

是否为移植项目：**否。基于 Linux RTNetlink 协议规范的 MoonBit 原生实现，非特定开源项目的整体移植。**

## 项目简介

MoonNetlink 为 MoonBit 程序提供类型化的 Linux 网卡、地址、路由和邻居表查询、受支持资源的修改，以及网络变化监听能力，并在基础 SDK 之上提供 `snapshot → diff → plan → apply → verify` 的声明式配置工作流。项目面向容器网络工具、VPN 与网关程序、网络监控与诊断工具，以及网络命名空间实验和自动化测试的开发者，提供可复用的网络管理基础设施。

项目采用 MoonBit 实现协议编解码、领域模型、异步请求处理、状态规划与执行验证；C shim 仅承担打开 Linux socket、设置选项和移交描述符所有权的最小原生边界。SDK 通过 RTNetlink 与内核交互，不通过调用 `ip` 命令实现查询或修改。项目同时交付公共 API、CLI、隔离演示和验证脚本，使协议能力能够被其他 MoonBit 项目使用，并形成从观察、审查到执行、验证的完整流程。

## 核心功能范围

### 当前已实现

1. **纯 MoonBit Netlink 编解码。** 支持消息头、四字节对齐、TLV 属性、多部分响应、ACK/DONE 控制消息与扩展错误诊断；校验输入长度和访问边界，保留未知属性。
2. **类型化网络模型与查询。** 提供 Link、Address、Route、Neighbor 模型和导出查询，支持按接口名称或索引查询 Link，以及严格的 IPv4、IPv6、MAC 文本解析与规范化输出。
3. **明确范围的网络修改。** 支持接口 UP/DOWN、MTU 修改、IPv4/IPv6 本地地址和单播路由添加、删除，提供排他添加与显式替换模式，保留内核 errno 和可用的 extack 诊断。
4. **异步请求与变化监听。** 基于 `moonbitlang/async` 管理请求串行化、序列号匹配、超时和资源关闭；通过独立组播 socket 监听类型化 Link、Address、Route、Neighbor 事件，并明确报告事件丢失。
5. **网络快照与严格目标配置。** 提供拥有数据所有权的快照、确定性 JSON、版本化 DesiredState schema，以及显式 `present/absent` 意图；校验字段、范围与资源身份冲突，不删除未声明的资源。
6. **可审查的 Diff 与 Plan。** 根据实际快照与目标状态生成确定性差分和有序操作计划，列出精确参数、原因和危险标记，正确处理添加、删除及接口状态的依赖顺序。
7. **默认预演与资源保护。** `plan` 和未确认 `apply` 只读；执行需显式 `--yes`，回环接口、默认路由修改另需 `--dangerous`，并在写入前检查接口身份和整个计划。
8. **部分失败报告与尽力补偿。** 按顺序执行，首个失败即停止，记录已完成、失败、未执行项和结果不确定性；对已确认且可补偿的操作倒序补偿，保留原始错误及各项补偿结果。
9. **执行后验证与幂等性。** 执行或补偿后重新查询实际状态，只有执行完成且目标差分为空才报告成功；隔离集成验证覆盖第一次 apply 达成目标、第二次 plan 为空及第二次 apply 无操作。
10. **可复现工程交付。** 提供 SDK 容器初始化、声明式收敛、并行监听与受控失败四类隔离演示，使用 `ip -j` 独立对拍；提供固定 seed 的未知属性、顺序、截断、错误长度和嵌套输入检查，以及中英双语 README 和说明文档。

截至 2026-10-04，现有源码验证记录包括 Windows native **109/109**、Linux native **116/116** 测试通过，以及干净源码归档下的隔离集成和演示验证。Linux 验证目前基于已有本地 / WSL2 环境，自动 CI 和更多独立环境验证仍属于后续交付。

当前面向 **Linux / MoonBit native**；修改需要调用进程所在网络命名空间内的网络管理权限。接口创建、删除，多路径路由、策略规则和其他 Netlink family 不属于当前修改范围。快照不是原子内核快照，失败恢复是尽力补偿，不承诺原子事务或完整替代 iproute2。

### 后续交付计划

完善覆盖率与性能基线、分配和拷贝分析、Linux 验证环境记录；接入自动构建和隔离集成 CI；完成 Mooncakes 包发布、独立 consumer 安装验证与版本发布。以上内容按后续任务验收，不作为当前已完成成果。

## 移植或参考说明

原项目名称：**不适用。项目不是对单一现有库的整体移植。**

原项目链接：**不适用。协议依据和设计对照对象见下方。**

原项目许可证：**不适用。没有指定的移植上游；实际引用内容的来源和许可需分别记录。**

本项目许可证：**MIT**，见仓库 [LICENSE](../LICENSE)。

协议依据为 Linux 官方 [Netlink 入门文档](https://docs.kernel.org/userspace-api/netlink/intro.html)、[rt-route 协议族规范](https://www.kernel.org/doc/html/v6.16/networking/netlink_spec/rt-route.html) 和 Linux UAPI。成熟 API 的设计对照对象包括 [Go netlink](https://github.com/vishvananda/netlink)、[Rust netlink 生态](https://github.com/rust-netlink)；[iproute2](https://git.kernel.org/pub/scm/network/iproute2/iproute2.git/) 用于行为对照与实际状态核验。它们不构成本项目已整体移植的上游。

本项目采用以下实现取舍与设计：

- 使用 MoonBit 原生包结构、类型系统和测试方式组织代码，以类型化值和错误表达 Linux 网络对象及失败原因。
- 将纯协议、领域模型、Linux I/O、状态规划和执行验证分层，保持核心解析与状态逻辑可脱离内核权限测试。
- 首期聚焦 `NETLINK_ROUTE` 的可验证子集，保留未知属性，为后续扩展留出空间；不承诺一次性复刻 iproute2。
- 在 SDK 之上提供显式确认、关键资源保护、部分失败报告与重新观测验证，服务实际配置流程。
- 以公共 MoonBit API 和 CLI 为主要交付接口，用真实命名空间测试、差分对拍和受控失败演示提供工程证据。

---

# MoonNetlink Project Proposal — English Version

## Basic Information

Project title: **MoonNetlink: A MoonBit-native Linux RTNetlink SDK and Declarative Network State Toolkit**

Participant: **To be completed**

Contact information: **To be completed**

GitHub repository: [Eisem/moon_netlink](https://github.com/Eisem/moon_netlink.git)

Project category: **MoonBit systems programming library / Linux network management and cloud-native infrastructure**

Porting project: **No. A MoonBit-native implementation based on Linux RTNetlink protocol specifications, rather than a complete port of a specific open-source project.**

## Project Overview

MoonNetlink provides MoonBit programs with typed queries for Linux links, addresses, routes and neighbors, mutations for supported resources, and network change monitoring. It adds a declarative `snapshot → diff → plan → apply → verify` workflow on top of the SDK. The project serves developers of container networking tools, VPN and gateway programs, network monitoring and diagnostics, and network namespace experiments and automated tests with reusable network management infrastructure.

Protocol encoding/decoding, domain models, asynchronous request handling, state planning and execution verification are implemented in MoonBit. The C shim is limited to opening the Linux socket, setting options and transferring descriptor ownership. The SDK communicates with the kernel through RTNetlink and does not invoke `ip` to perform queries or mutations. Public APIs, a CLI, isolated demonstrations and validation scripts support downstream MoonBit projects and a complete observation, review, execution and verification workflow.

## Core Functional Scope

### Implemented Capabilities

1. **Pure MoonBit Netlink codec.** Message headers, four-byte alignment, TLV attributes, multipart responses, ACK/DONE controls and extended diagnostics, with checked lengths/access boundaries and preserved unknown attributes.
2. **Typed network models and queries.** Link, Address, Route and Neighbor dumps; Link point queries by name or index; strict IPv4/IPv6/MAC parsing and canonical output.
3. **Scoped network mutations.** Link UP/DOWN and MTU changes, local IPv4/IPv6 address and unicast route addition/deletion, exclusive creation and explicit replacement, preserving kernel errno and available extack diagnostics.
4. **Asynchronous requests and monitoring.** `moonbitlang/async` handles serialized requests, sequence matching, timeouts and resource closure. An independent multicast socket delivers typed Link/Address/Route/Neighbor events and reports event loss.
5. **Snapshots and strict desired configuration.** Owned snapshots, deterministic JSON, a versioned DesiredState schema and explicit `present/absent` intent, with field/range/conflict validation and no deletion of undeclared resources.
6. **Reviewable Diff and Plan.** Deterministic differences and ordered operations from observations and desired state, including exact arguments, reasons, danger markers and add/delete/link-state dependencies.
7. **Default dry-run and resource protection.** Plan and unconfirmed apply are read-only. Execution requires `--yes`; loopback/default-route changes additionally require `--dangerous`, with interface identity and whole-plan checks before writing.
8. **Partial-failure reporting and best-effort compensation.** Ordered execution stops at its first failure and records completed, failed, skipped and uncertain outcomes. Acknowledged compensable operations are reversed, preserving the original cause and every compensation result.
9. **Post-execution verification and idempotence.** Fresh queries after execution or compensation; success requires completed execution and an empty desired-state difference. Isolated integration checks prove successful first apply, empty second plan and no-op second apply.
10. **Reproducible engineering deliverables.** Four isolated demonstrations cover SDK container initialization, declarative convergence, concurrent monitoring and controlled failure, with independent `ip -j` comparison. Fixed-seed tests exercise unknown attributes, ordering, truncation, corrupt lengths and nesting. README and explanatory documentation are bilingual.

As of 2026-10-04, existing source validation records include **109/109 Windows native tests** and **116/116 Linux native tests**, plus isolated integration and demonstration checks from a clean source archive. Linux validation currently uses the available local / WSL2 environment; automated CI and further independent environments remain planned work.

The current target is **Linux / MoonBit native**. Mutations require network administration privileges in the calling process's network namespace. Link creation/deletion, multipath routes, policy rules and other Netlink families are outside the current mutation scope. Snapshots are not atomic kernel snapshots, and recovery is best-effort compensation, not an atomic transaction or a complete iproute2 replacement.

### Planned Deliverables

Complete coverage and performance baselines, allocation/copy analysis and Linux environment records; add automated build and isolated integration CI; publish the Mooncakes package and validate installation from an independent consumer, followed by a versioned release. These items require their own acceptance checks and are not claimed as completed.

## Porting and Reference Notes

Original project: **Not applicable; this is not a complete port of one existing library.**

Original project URL: **Not applicable; protocol references and design comparisons are listed below.**

Original project license: **Not applicable; no porting upstream is designated. Sources and licenses of actual reused material must be recorded separately.**

Project license: **MIT**, as recorded in [LICENSE](../LICENSE).

Protocol references are the official Linux [Netlink introduction](https://docs.kernel.org/userspace-api/netlink/intro.html), [rt-route specification](https://www.kernel.org/doc/html/v6.16/networking/netlink_spec/rt-route.html) and Linux UAPI. Mature API design comparisons include [Go netlink](https://github.com/vishvananda/netlink) and the [Rust netlink ecosystem](https://github.com/rust-netlink). [iproute2](https://git.kernel.org/pub/scm/network/iproute2/iproute2.git/) supports behavior comparison and actual-state validation. These are not claimed as completely ported upstream projects.

Implementation choices:

- Use MoonBit-native packages, types and tests, expressing network objects and failure causes as typed values and errors.
- Separate pure protocol, domain models, Linux I/O, state planning and execution verification, allowing core parsing/state tests without kernel privileges.
- Focus on a verifiable `NETLINK_ROUTE` subset, preserving unknown attributes for extension without promising a complete iproute2 reimplementation.
- Add explicit confirmation, critical-resource protection, partial reports and fresh verification on top of the SDK for real configuration workflows.
- Deliver public MoonBit APIs and a CLI, supported by actual namespace tests, differential checks and controlled-failure demonstrations.
