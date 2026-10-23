# P0 delivery plan / P0 交付计划

## Coverage and fault evidence / 覆盖率与故障证据

1. Collect native compiler counters with the locked Linux toolchain; preserve XML
   and HTML reports and document what is not measured.
2. Gate all five library packages against reviewed covered-line counts and ratios.
3. Require nine named critical fault tests to execute exactly once and pass.
4. Run the same entry point in clean CI and retain the report.

1. 使用锁定 Linux 工具链采集 native 计数，保存 XML、HTML，说明未测量的范围。
2. 五个库包分别按已审查的覆盖行数及比例执行回归门禁。
3. 九项命名关键故障测试必须各执行一次且通过。
4. 干净 CI 使用同一入口并保留报告。

Implementation and local acceptance are complete; see [coverage](coverage.md).
Remote results belong to the corresponding GitHub Actions run, rather than to
this plan. Do not automatically lower baselines to make CI pass.

实现及本地验收已完成，见[覆盖率说明](coverage.md)。远程结果以对应 GitHub
Actions 运行为准，本计划不替代执行证据。不得为通过 CI 自动降低基线。

## Repeatable releases / 可重复发布

1. Move archive URLs, compiler versions and SHA256 digests into a reviewed lock.
2. Verify archives on every use; allow content-addressed offline caches and share
   the cache across workflows without fallback to another toolchain version.
3. Build Linux x86_64 CLI and source archives from a clean tagged commit. Include
   provenance, dependency notices, runtime linkage requirements and checksums.
4. Verify checksums and run the extracted binary before uploading. Manual runs
   produce reviewable artifacts; version tags publish them only after build gates.

1. 归档 URL、编译器版本及 SHA256 放入可审查的锁文件。
2. 每次使用均校验归档；支持内容寻址离线缓存，工作流共享缓存，不回退到其他版本。
3. 从干净的标签提交构建 Linux x86_64 CLI 及源码归档，附来源、依赖声明、运行库要求及校验和。
4. 上传前校验摘要并运行解压后的二进制。手动运行生成可审查产物；版本标签仅在构建门禁通过后发布。

Upstream currently serves the verified toolchain at mutable `latest` URLs;
historical URL probes returned 403. The cache removes that dependency for repeat
installs **while the verified archives are retained**. GitHub caches can be
evicted. This is a documented availability limitation, not a promise of permanent
upstream archival. Operators should retain the two locked archives in their own
backup and set `MOONNETLINK_TOOLCHAIN_CACHE` to that directory. A missing cache
and changed upstream archive intentionally fail rather than silently upgrade.
This project distributes its own release artifacts, not a repackaged compiler.

上游当前通过可变 `latest` URL 提供已验证工具链；历史版本 URL 探测返回 403。
**保留已验证归档期间**，缓存可使重复安装不依赖这些 URL；GitHub 缓存可能被回收。
这是已知可用性限制，不承诺上游永久存档。维护者应另行备份锁定的两个归档，并将
`MOONNETLINK_TOOLCHAIN_CACHE` 指向备份目录。缓存缺失且上游内容已变更时会明确
失败，不会静默升级。本项目分发自己的发布产物，不重新打包分发编译器。

The archive layout and source timestamps are normalized. Host C compiler, libc
and native build paths can still affect executable bytes; the process records
them and makes no cross-host bit-for-bit reproducibility claim. The supported
binary target is Linux x86_64; consult `RUNTIME.txt` for the actual dynamic loader
and shared-library requirements of each build.

归档布局及源码时间戳已规范化。宿主 C 编译器、libc 及原生构建路径仍可能影响
可执行文件字节；流程记录其信息，不声称跨宿主逐字节一致。二进制目标为 Linux
x86_64；各次构建实际动态加载器及共享库要求见 `RUNTIME.txt`。
