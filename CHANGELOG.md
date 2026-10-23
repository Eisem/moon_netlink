# Changelog / 更新记录

## 0.1.1

- Add per-package native line coverage regression gates and nine mandatory fault regressions.
- Verify published-package queries, typed monitoring, IPv4/IPv6 reconciliation, idempotence and protection in a standalone consumer.
- Pin toolchain archive digests, retain a verified offline cache, and build Linux x86_64 release archives with checksums and provenance.
- Normalize source and generated interfaces for MoonBit 0.1.20261021. The runtime API uses canonical Int32/UInt32 names; defaulted labeled arguments keep the same calling behavior.
- Live networking requires Linux/native. Mutations require network administration privileges. Compensation is best effort, snapshots are not atomic, and timeouts can leave outcomes unknown.

- 新增分包 native 行覆盖率回归门禁及九项必须执行的故障回归。
- 独立 consumer 验证已发布包的查询、类型化监听、IPv4/IPv6 收敛、幂等与保护。
- 固定工具链归档摘要，保留已验证离线缓存，生成含校验和及来源信息的 Linux x86_64 发布归档。
- 源码及生成接口适配 MoonBit 0.1.20261021，采用规范 Int32/UInt32 名称；带默认值的标签参数保持原调用行为。
- 真实网络操作需要 Linux/native，修改需要网络管理权限。补偿属于尽力恢复；快照非原子，超时可能导致结果未确定。

## 0.1.0

Initial Mooncakes release: typed RTNetlink codecs, Link/Address/Route/Neighbor
queries and events, supported link/address/route mutations, snapshots, strict
desired-state parsing, plans, protection, ordered execution, compensation and
final verification.

首次 Mooncakes 发布：类型化 RTNetlink 编解码，链路、地址、路由、邻居查询及事件，
已支持的链路、地址、路由修改，快照、严格目标状态解析、计划、保护、顺序执行、
补偿及最终验证。
