# Core codec contract / 核心编解码约定

The `core` package owns the transport-independent Netlink wire format. It has
no socket dependency and can be tested on any native host supported by this
module.

`core` 包负责独立于传输层的 Netlink 二进制格式，不依赖 socket，可在本模块支持的任意 native 主机上测试。

## Messages and alignment / 消息与对齐

`decode_datagram` validates each 16-byte Netlink header before reading its
payload. A message length smaller than the header, larger than the remaining
datagram, or too large for MoonBit's signed indexing produces a structured
`CodecError`. Multipart datagrams advance by four-byte `NLMSG_ALIGN` boundaries;
a zero or invalid length cannot stall the parser.

`decode_datagram` 在读取载荷前校验每个 16 字节 Netlink 头。消息长度小于头部、超出剩余数据报，或超过 MoonBit 有符号索引范围时，会返回结构化的 `CodecError`。多部分数据报按四字节 `NLMSG_ALIGN` 边界前进；零长度或非法长度不会使解析器停滞。

`encode_message` derives `nlmsg_len` from the owned payload rather than trusting
the caller's header length. It emits zero-filled alignment bytes. Decoding and
re-encoding therefore preserves message semantics, but deliberately normalizes
padding and length fields.

`encode_message` 根据自身拥有的载荷计算 `nlmsg_len`，不信任调用者提供的头部长度，并用零填充对齐字节。因此，解码后再编码保留消息语义，同时规范化填充和长度字段。

## Attributes / 属性

`decode_attributes` separates the base attribute type from Linux's
`NLA_F_NESTED` and `NLA_F_NET_BYTEORDER` bits. Unknown base types remain ordinary
`NetlinkAttribute` values with their payload bytes intact. `encode_attribute`
reconstructs both flag bits, zero-fills alignment padding, and rejects a value
that cannot fit the 16-bit `nla_len` field.

`decode_attributes` 将基础属性类型与 Linux 的 `NLA_F_NESTED`、`NLA_F_NET_BYTEORDER` 标志分开。未知类型仍以普通 `NetlinkAttribute` 表示，保留完整载荷字节。`encode_attribute` 恢复这两个标志、用零填充对齐字节，并拒绝无法放入 16 位 `nla_len` 的值。

## Generic control messages / 通用控制消息

`decode_control` distinguishes family messages from `NLMSG_NOOP`, `NLMSG_DONE`,
`NLMSG_ERROR`, and `NLMSG_OVERRUN`. An `NLMSG_ERROR` payload with errno zero is
an `Ack`; a nonzero errno is normalized to a positive `KernelError` code while
retaining the embedded request header. Malformed control payloads return
`CodecError` rather than panicking.

`decode_control` 区分协议族消息与 `NLMSG_NOOP`、`NLMSG_DONE`、`NLMSG_ERROR`、`NLMSG_OVERRUN`。`NLMSG_ERROR` 的 errno 为零时表示 `Ack`；非零时转换为正值 `KernelError`，并保留内嵌请求头。畸形控制载荷返回 `CodecError`，不会触发 panic。

The transport waits for `Done` to finish a dump. Receiving an `Ack` alone no
longer ends a multipart request, and a nonzero `Done` status is surfaced as a
kernel rejection.

传输层等待 `Done` 才结束导出。单独收到 `Ack` 不会结束多部分请求；`Done` 的非零状态会作为内核拒绝上报。

## Extended acknowledgements / 扩展确认诊断

`decode_extended_ack` returns `None` unless `NLM_F_ACK_TLVS` is set. For
`NLMSG_ERROR`, it skips the embedded header and, for uncapped failures, the
aligned echoed request body. Success ACKs and `NLM_F_CAPPED` errors do not
echo that body. `NLMSG_DONE` diagnostics begin after the four-byte status.
Every offset and attribute length is checked before access.

只有设置 `NLM_F_ACK_TLVS` 时，`decode_extended_ack` 才返回扩展诊断，否则返回 `None`。对 `NLMSG_ERROR`，它跳过内嵌请求头；未设置 capped 的失败还需跳过对齐后的回显请求体。成功 ACK 和 `NLM_F_CAPPED` 错误不会回显请求体。`NLMSG_DONE` 的诊断从四字节状态之后开始。所有偏移与属性长度均在访问前检查。

`ExtendedAck` exposes message text, offending offset, cookie, missing
attribute type/nesting offset, and unknown attributes. Text requires valid
UTF-8 and a single terminal NUL; integer attributes require exactly four
bytes. Unknown attributes and opaque cookies retain their bytes. The existing
`NetlinkControl` API remains compatible; extended diagnostics are a separate
decoder. Layout follows the official Linux
[Netlink introduction](https://docs.kernel.org/userspace-api/netlink/intro.html).

`ExtendedAck` 提供消息文本、出错偏移、cookie、缺失属性类型或嵌套偏移，以及未知属性。文本必须是有效 UTF-8，并且只有一个末尾 NUL；整数属性必须恰好四字节。未知属性和不透明 cookie 保留原始字节。现有 `NetlinkControl` API 保持兼容，扩展诊断使用独立解码器。布局遵循 Linux 官方 [Netlink 入门文档](https://docs.kernel.org/userspace-api/netlink/intro.html)。
