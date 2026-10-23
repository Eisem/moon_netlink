# Release and downstream validation / 发布与下游验证

`eisem/moonnetlink@0.1.0` is published on Mooncakes. It requires the native backend,
a C compiler and Linux for live networking. The tested toolchain is MoonBit
`0.1.20260920`, with `moonbitlang/async@0.22.1`.

`eisem/moonnetlink@0.1.0` 已发布至 Mooncakes。真实网络操作要求 Linux、native
后端和 C 编译器。已测试工具链为 MoonBit `0.1.20260920`，依赖为
`moonbitlang/async@0.22.1`。

```sh
moon add eisem/moonnetlink@0.1.0
```

Import the packages your application uses in `moon.pkg`:

在应用的 `moon.pkg` 中导入所需包：

```moonbit
import {
  "eisem/moonnetlink/transport",
  "eisem/moonnetlink/state",
  "eisem/moonnetlink/reconcile",
  "moonbitlang/async",
}
```

See `examples/inspect_links` for queries and `examples/network_config_app` for
planning, protection, execution and application decisions. Close clients after use.
The `core` and `route` packages expose protocol codecs and typed models.

查询示例见 `examples/inspect_links`；规划、保护、执行与应用判定见
`examples/network_config_app`。使用后应关闭客户端。`core` 与 `route` 包提供
协议编解码与类型化模型。

## Automated checks / 自动检查

`.github/workflows/ci.yml` checks formatting, compilation, builds, tests and public
interfaces on Ubuntu 24.04. `.ci/install-toolchain.sh` verifies SHA256 digests of
the official Linux toolchain and core archives before extraction. Their `latest`
URLs are mutable: a changed archive fails CI until both digests are deliberately
reviewed and updated. Historical `0.1.20260920` downloads returned HTTP 403.
Kernel acceptance and the
comparison scenario run in disposable user/network namespaces. Namespace failure
fails the job. Workflow configuration is not evidence of a successful remote run.

`.github/workflows/ci.yml` 在 Ubuntu 24.04 检查格式、编译、构建、测试与公共接口。
`.ci/install-toolchain.sh` 在解压前校验官方 Linux 工具链及 core 归档的 SHA256。
`latest` URL 内容可能变化；归档变化将使 CI 失败，直到审查并更新两个摘要。
历史 `0.1.20260920` 下载返回 HTTP 403。
内核验收与对照场景运行于临时用户及网络命名空间；创建失败会使
任务失败。工作流配置本身不代表远程执行已经通过。

`.ci/validate-consumer.sh` creates a temporary standalone module outside this
checkout, installs exactly version `0.1.0` from the registry, builds its C shim and
queries live Linux links through public APIs. In a disposable namespace it also
checks dry-run, IPv4/IPv6 address and route configuration, a typed MTU event,
zero-operation repetition, deletion, unmanaged address preservation and loopback
protection with zero mutation attempts. Only application examples and the monitor
probe are copied; no SDK implementation or local dependency override is used. It requires
registry availability and index propagation. The consumer workflow runs manually
or after a GitHub release. Namespace creation failure fails the check; it does
not silently skip the mutation scenarios. All subprocesses have bounded waits,
and temporary files and monitor processes are cleaned up on failure.

`.ci/validate-consumer.sh` 在检出目录外创建临时独立模块，从注册表安装固定版本
`0.1.0`，构建其 C shim，并通过公共 API 查询真实 Linux 链路。在临时命名空间中
还验证 dry-run、IPv4/IPv6 地址及路由配置、类型化 MTU 事件、重复执行零操作、
删除、未管理地址保留，以及零修改尝试的回环接口保护。仅复制应用示例及监听探针，
不复制 SDK 实现，也不使用本地依赖替代。它需要注册表可访问且索引已同步。
consumer 工作流支持手动运行及 GitHub release 后运行。命名空间创建失败会使
检查失败，不会静默跳过修改场景。所有子进程均有等待上限，失败时清理临时文件及
监听进程。

```sh
bash .ci/validate-consumer.sh
```

## Version policy / 版本策略

The 0.x API can evolve. Pin versions, review generated interfaces and test your
application before upgrading. Compensation is best effort; snapshots are not
atomic and a timeout can leave an operation's outcome unknown. See the transport
and reconciliation documentation for these contracts.

0.x API 可能演进。应固定版本，审查生成接口，并在升级前验证应用。补偿属于尽力
恢复；快照不具备原子性，超时可能导致操作结果未确定。相关约定见传输及收敛文档。
