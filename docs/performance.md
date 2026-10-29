# Query performance baseline / 查询性能基线

```sh
bash .ci/benchmark-queries.sh --interfaces 32 --samples 30 --warmup 5
```

Requires Linux x86_64, the locked MoonBit toolchain, a C compiler, Python 3,
iproute2 and permission to create user/network namespaces. The wrapper builds
the release CLI before measurement, then creates a disposable namespace with
loopback plus 32 dummy interfaces. Setup and teardown are outside the measured
work. Namespace destruction cleans up interfaces on success or failure; no host
interface is configured. Namespace failure fails the command without fallback.

要求 Linux x86_64、锁定的 MoonBit 工具链、C 编译器、Python 3、iproute2 及创建
用户/网络命名空间的权限。包装脚本在计时前构建 release CLI，在临时命名空间内
创建回环及32个dummy接口。准备及清理不计时。成功或失败后均由命名空间销毁清理
接口，不配置宿主接口；命名空间失败时直接报错，不回退到宿主运行。

Each sample runs either `moonnet link show --json` or `ip -j link show` as a new
process, captures stdout and parses it with Python JSON. `perf_counter_ns` measures
that complete interval. Every result must match a fixed initial observation for
interface index, name, MTU and administrative UP state. Ordering is normalized
outside timing. Duplicate indices or changed observations invalidate the run.
Both commands query all interfaces, but their output schemas and output sizes
differ; byte counts are recorded and this is not an identical-serialization test.

每个样本新建进程运行 `moonnet link show --json` 或 `ip -j link show`，捕获输出并
使用 Python JSON 解析。`perf_counter_ns` 测量整个区间。每次结果的接口索引、名称、
MTU及管理UP状态必须与固定初始观测一致；排序规范化在计时外执行。索引重复或观测
变化会使运行失败。双方均查询全部接口，但输出schema及字节数不同；报告记录字节数，
不将其视为完全相同的序列化工作量。

Five warmup queries per side are discarded. The next 30 per side are retained,
alternating which side runs first. `_build/benchmarks/queries.json` records raw
nanoseconds, min/mean/median/nearest-rank p95/max, object counts, command lines,
source commit, kernel, CPU model/count, Python, toolchain and iproute2 versions.
Bounds: 1–1000 dummy interfaces, 2–1000 measured samples, 1–100 warmup samples.
Queries have a 30-second timeout. A failed run removes any previous report at the
selected output path; it cannot leave stale results presented as a new success.

双方各丢弃5次预热，随后各保留30次采样，交替先运行的一方。
`_build/benchmarks/queries.json` 保存原始纳秒数、最小值/均值/中位数/最近秩p95/
最大值、对象数、命令、源码提交、内核、CPU型号及数量、Python、工具链和iproute2
版本。范围：1–1000个dummy接口，2–1000次采样，1–100次预热；每次查询限时30秒。
运行开始后删除所选输出路径中的旧报告，失败不会将旧数据伪装成新结果。

The manual `Query performance baseline` workflow retains the JSON as an artifact.
Shared CI runners, CPU scheduling and warm caches affect timings. Compare runs
only with equivalent environments and inspect raw distributions. There is no
speed threshold or claim that one side is faster. This measures CLI end-to-end
latency, not in-process SDK latency, isolated codec throughput, memory usage or
allocation counts. Those require separate benchmarks before changing buffer
ownership, copying or request concurrency.

手动 `Query performance baseline` 工作流保存JSON产物。共享CI运行器、CPU调度及
热缓存均影响结果；应在相当环境下比较并审查原始分布。当前没有速度门槛，也不宣称
哪一方更快。这是CLI端到端延迟，不是进程内SDK延迟、独立编解码吞吐、内存或分配
计数；修改缓冲区所有权、拷贝或请求并发前，仍需建立对应的独立基线。
