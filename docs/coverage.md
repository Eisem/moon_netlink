# Coverage and fault gates / 覆盖率与故障门禁

Run on Linux with the locked toolchain:

在 Linux 使用锁定工具链运行：

```sh
bash .ci/check-coverage.sh
```

The gate clears old counters, runs native tests with instrumentation and writes
Cobertura XML plus an HTML report to `_build/coverage/`. CI retains these reports.
It excludes the CLI, examples and dependencies from the library baseline and
requires all five library packages to have instrumentation.

门禁清理旧计数，运行带插桩的 native 测试，在 `_build/coverage/` 输出 Cobertura
XML 和 HTML 报告，CI 保存这些报告。库基线不包含 CLI、示例及依赖，五个库包均须
存在插桩数据。

| Package / 包 | Covered lines / 已覆盖行 | Instrumented lines / 插桩行 | Rate / 比例 |
| --- | ---: | ---: | ---: |
| core | 126 | 136 | 92.65% |
| route | 373 | 428 | 87.15% |
| state | 327 | 392 | 83.42% |
| transport | 120 | 198 | 60.61% |
| reconcile | 101 | 134 | 75.37% |

Baseline: MoonBit 0.1.20261021, async 0.22.1, Linux x86_64, 121 native tests.
This measures executable **line coverage**, not branch coverage. Compiler counters
do not measure C shim coverage. Linux excludes Windows-only code at compilation.
Namespace integration tests run separately without instrumentation; their execution
is not added to these percentages. In particular, transport mutation paths exercised
by integration can remain uncovered here. The HTML report identifies the actual
uncovered lines; these limitations are not exemptions from the numeric gate.

基线环境：MoonBit 0.1.20261021、async 0.22.1、Linux x86_64、121 项 native 测试。
这里测量可执行代码的**行覆盖率**，不是分支覆盖率。编译器计数不包含 C shim；
Windows 专属代码在 Linux 编译时排除。命名空间集成测试单独运行且没有插桩，
其执行不计入上述百分比。因此集成测试已执行的 transport 修改路径仍可能显示
未覆盖。实际未覆盖行见 HTML 报告；这些限制不构成数值门禁的豁免。

Each package must preserve both its exact coverage ratio (integer cross-product
comparison, without rounding tolerance) and its covered-line count. Added untested
code, missing packages, and unexplained covered-code removal fail the gate. A
legitimate refactor or removed feature can require a baseline update; review the
source diff and HTML report before explicitly regenerating it:

每个包必须同时保持精确覆盖比例（使用整数交叉相乘，不做舍入容差）及已覆盖行数。
新增未测试代码、缺失包、未说明的已覆盖代码删除会使门禁失败。合理重构或功能删除
可能需要调整基线；先审查源码差异及 HTML 报告，再显式重新生成：

```sh
python3 .ci/coverage_gate.py _build/coverage/cobertura.xml --write-baseline
```

`.ci/critical-tests.json` independently names nine fault regressions: malformed
lengths, interrupted dumps, event loss, monitor cancellation, loopback protection,
execution cancellation, uncertain timeout outcomes, compensation failure and
ineffective ACK verification. Each must execute exactly once and pass. Renaming,
removing or skipping a test fails until the manifest is reviewed. The full suite
still runs afterward. New failure semantics should add a named regression and
update this manifest; neither a high percentage nor these nine tests prove all
possible branches safe.

`.ci/critical-tests.json` 独立列出九项故障回归：畸形长度、中断导出、丢事件、监听
取消、回环保护、执行取消、超时结果未确定、补偿失败及无效 ACK 后验证。每项必须
恰好执行一次且通过；重命名、删除或跳过测试都会失败，直至审查并更新清单。
随后仍运行完整测试集。新增失败语义应增加命名回归并更新清单；高覆盖比例及这九项
测试均不证明所有分支安全。
