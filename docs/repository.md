# 提交文件与本地文件

仓库保存重现源码、公共 API、测试和示例所需的文件。构建结果、下载的依赖和本地资料
保留在工作区，由 `.gitignore` 排除；不需要为了提交而删除它们。

| 文件或目录 | 是否提交 | 原因 |
| --- | --- | --- |
| `moon.mod`、各包的 `moon.pkg` | 是 | 模块元数据、固定版本的依赖与构建配置 |
| `core/`、`route/`、`transport/` 的 `.mbt`、C shim | 是 | SDK 实现与原生 socket 边界 |
| `state/` 的 `.mbt` | 是 | Snapshot、严格配置 schema、显式意图、Diff 和 Plan 的纯状态实现 |
| `*_test.mbt`、`*_wbtest.mbt` | 是 | 纯协议、失败路径和 Linux 回归测试；fixtures 内嵌于测试源码 |
| `pkg.generated.mbti` | 是 | `moon info --target native` 生成的公共 API 审查记录，不能手工修改 |
| `cmd/moonnet/`、`examples/` | 是 | 查询、JSONL 监听及隔离修改示例 |
| `.ci/*.sh`、`.ci/*.py` | 是 | 可复现的隔离 namespace 验证与 `ip -j` 差分脚本 |
| `README.md`、`docs/`、`LICENSE` | 是 | 使用方式、公开实现进度、协议和安全约定、许可证 |
| `.gitignore`、`.gitattributes` | 是 | 提交边界与跨平台 LF 换行规则 |
| `_build/`、`target/` | 否 | 可重新生成的构建、测试和文档产物 |
| `.mooncakes/` | 否 | 通过 `moon update` 下载的依赖；版本由 `moon.mod` 记录 |
| `TODO.md` | 否 | 本地工程指导和任务记录；不暂存、不提交、不推送，更新留在工作区 |
| 编译链接产物、Python 缓存、日志、临时文件 | 否 | 本地运行结果，不属于源码 |
| `.env*`（示例除外）、`.aws/`、`.codex/`、`.agents/` | 否 | 本地凭据或运行状态 |
| `MoonBit 黑客松大赛章程/` | 否 | 本地参考资料，不是项目实现或项目发布内容 |
| `.git/` | 否 | Git 自己维护的历史与本地配置，不作为源码文件提交 |

`.ci/` 中的脚本目前需要手动运行；它们不是已配置的 GitHub Actions 工作流。
Phase 4 已完成 Snapshot/DesiredState/Diff/Plan；保护、dry-run CLI、Apply 与后续
发布任务仍未完成。公开能力与限制以 README 和相关 API 文档为准。

每个小任务完成并验收后独立提交，实现、测试、公开文档和生成接口一同交付。
任务勾选与内部指导仅更新本地 `TODO.md`，不能把该文件加入任务 commit。

提交前检查：

```sh
moon check --target native --warn-list +73
moon test --target native
moon fmt --check
moon info --target native
git status --short
git status --ignored --short
git diff --check
git diff --cached --check
git diff --cached --stat
```

Linux 隔离验收：

```sh
bash .ci/validate-queries.sh
bash .ci/validate-link-state.sh
bash .ci/validate-mutations.sh
```

新增源码应明确加入暂存区，再检查暂存清单。不要用 `git add -f` 将被忽略的本地文件
混入提交。推送前读取远程分支状态；已有远程提交应保留，不使用强制推送。
