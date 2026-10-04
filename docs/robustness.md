# Reproducible protocol robustness / 可复现协议健壮性验证

```sh
bash .ci/validate-robustness.sh
```

The Linux wrapper limits each package's build/test process to 120 seconds and
kills the process group after a further five seconds. A timeout, panic or
unexpected outcome fails the command. These pure tests also run in the ordinary
Windows native test suite; the wrapper requires GNU `timeout`.

Linux 包装脚本将每个包的构建、测试进程限制为 120 秒，再等待最多五秒后终止进程组。超时、panic 或结果不符均使命令失败。这些纯测试也运行在常规 Windows native 测试集中；包装脚本需要 GNU `timeout`。

| Seed (xorshift32)<br>seed（xorshift32） | Fixed budget<br>固定预算 | Assertions<br>断言 |
| --- | --- | --- |
| `0x4d4e4c31` | 512 chains, 1–16 attributes, payloads up to 31 bytes<br>512 组链，每组 1–16 个属性，载荷最多 31 字节 | Shuffled unknown attribute types, flags and nested child data survive encoding/decoding without changing order or payload<br>重排后的未知属性类型、标志和嵌套子数据经编解码仍保留顺序与载荷 |
| `0x4d4e4c32` | 512 messages/attributes, payloads 1–128 bytes<br>512 组消息和属性，载荷 1–128 字节 | Generated truncations and lengths below header size, beyond available input and above signed range produce their structured codec errors<br>生成的截断、低于头部长度、超出可用输入和有符号范围的长度产生结构化编解码错误 |
| `0x4d4e4c33` | 256 typed Link messages<br>256 组类型化 Link 消息 | Reordering name/MTU/kind and unknown attributes preserves the typed values; malformed nested child lengths are rejected<br>重排名称、MTU、kind 和未知属性不改变类型化值；畸形嵌套子长度被拒绝 |

There are no external randomness sources, network privileges or kernel writes.
Failures identify the fixed seed and iteration. Reproduce a failure with the
same test and seed, reduce its attribute list/payload while preserving the
error, and add the resulting wire bytes as a focused regression fixture before
changing the parser. The current run found no failing generated input, so no
new failure fixture is claimed.

测试不依赖外部随机源、网络权限或内核写入。失败报告固定 seed 和迭代序号。使用同一测试和 seed 重现后，在保留错误的前提下缩减属性列表、载荷，并在修改解析器前将所得字节加入独立回归样例。本次运行未发现生成输入失败，因此不声称新增了失败回归样例。

This bounded deterministic corpus supplements the hand-written malformed-input
fixtures. It is not an exhaustive fuzzing or proof of safety for every byte
sequence. Kernel I/O, cancellation, protection and compensation are covered by
their separate transport/reconciliation and isolated integration tests.

这组有界、确定性的语料补充手写畸形输入样例，不是穷尽式 fuzzing，也不证明每种字节序列都安全。内核 I/O、取消、保护和补偿由各自的传输、收敛测试及隔离集成测试覆盖。
