# Transport ownership and datagram contract / 传输所有权与数据报约定

This document records the Phase 0 transport decisions that are not obvious
from the public API.

本文记录 Phase 0 中无法仅从公共 API 看出的传输层设计决策。

## Descriptor ownership / 描述符所有权

`native_open_route_socket` initially returns a small native owner object. Its
finalizer closes the descriptor unless `take_fd` transfers it to
`moonbitlang/async/raw_fd.RawFd`. After transfer, only `RawFd` owns and closes
the descriptor. `RouteSocket::close` is idempotent.

`native_open_route_socket` 最初返回一个小型原生所有者对象。除非 `take_fd` 将描述符移交给 `moonbitlang/async/raw_fd.RawFd`，否则其终结器会关闭描述符。移交后只有 `RawFd` 拥有并关闭描述符；`RouteSocket::close` 是幂等的。

The ownership transfer applies even when `RawFd` registration raises an error;
this follows the `RawFd` contract and prevents a second close in MoonNetlink.

即使注册 `RawFd` 时抛出错误，所有权移交仍然生效；该行为遵循 `RawFd` 约定，避免 MoonNetlink 再次关闭同一描述符。

## Datagram reads / 数据报读取

`NETLINK_ROUTE` uses datagram semantics. One `RawFd::read` performs one
`read(2)` call and consumes one queued Netlink datagram. If the user buffer is
too small, Linux copies only the prefix and discards the remainder of that
datagram.

`NETLINK_ROUTE` 使用数据报语义。一次 `RawFd::read` 执行一次 `read(2)`，消耗一个已排队的 Netlink 数据报。用户缓冲区过小时，Linux 只复制前缀，并丢弃该数据报的剩余部分。

The current public `RawFd` API does not expose `recvmsg(2)`, `MSG_TRUNC`, or a
readiness-only wait. Consequently MoonNetlink cannot safely peek the exact
datagram size and then retry without building a larger event-loop integration.

当前公共 `RawFd` API 不提供 `recvmsg(2)`、`MSG_TRUNC` 或仅等待就绪的接口。因此，若不增加更完整的事件循环集成，MoonNetlink 无法安全地预读精确数据报大小后重试。

The Phase 0 policy is therefore:

因此 Phase 0 采用以下策略：

1. use a 256 KiB receive buffer by default;
   默认使用 256 KiB 接收缓冲区；
2. allow callers to configure the capacity when opening `RouteSocket`;
   允许调用者在打开 `RouteSocket` 时配置容量；
3. reject capacities smaller than a Netlink header;
   拒绝小于 Netlink 头部的容量；
4. if `read` returns exactly the buffer capacity, raise
   `DatagramMayBeTruncated` and discard the whole request result;
   `read` 返回字节数恰好等于容量时，抛出 `DatagramMayBeTruncated`，丢弃整个请求结果；
5. never feed a potentially truncated datagram into the protocol decoder.
   绝不将可能截断的数据报送入协议解码器。

An exact-size datagram produces a conservative false positive. This is
intentional: a false failure is safer than silently accepting incomplete
kernel state. Multipart dumps may span any number of datagrams; the capacity
limits each individual datagram, not the total dump size.

数据报恰好填满缓冲区时会产生保守的误报。这是有意选择：明确失败优于静默接受不完整的内核状态。多部分导出可以跨任意数量的数据报；容量限制的是每个数据报，而非整个导出大小。

The Linux-only white-box test `live Netlink datagram truncation fails closed`
opens a real route socket with a deliberately 16-byte capacity and verifies
that an `RTM_GETLINK` response raises `DatagramMayBeTruncated` before decoding.

仅在 Linux 运行的白盒测试 `live Netlink datagram truncation fails closed` 打开真实 route socket，故意将容量设为 16 字节，验证 `RTM_GETLINK` 响应在解码前抛出 `DatagramMayBeTruncated`。

If real workloads exceed this limit frequently, a future transport may add a
minimal `recvmsg(MSG_PEEK | MSG_TRUNC)` integration. It must preserve async
cancellation and single-reader guarantees before replacing this policy.

若实际负载经常超过容量上限，未来可增加最小的 `recvmsg(MSG_PEEK | MSG_TRUNC)` 集成；替换当前策略前必须保留异步取消和单读取者保证。

## Datagram writes / 数据报写入

Each Netlink request is passed to one `RawFd::write` call. A short write raises
`ShortWrite`; MoonNetlink never sends the remainder as a second datagram.

每个 Netlink 请求只调用一次 `RawFd::write`。短写会抛出 `ShortWrite`；MoonNetlink 不会把剩余部分作为第二个数据报发送。

## RouteClient and concurrency / RouteClient 与并发

`RouteClient` owns exactly one `RouteSocket` and serializes every typed query
and close operation with one async mutex. Sequence numbers are allocated only
inside that critical section, start at one, and wrap from `0xffffffff` back to
one so zero remains reserved. This prevents concurrent tasks from racing to
write requests or consume each other's datagrams.

`RouteClient` 恰好拥有一个 `RouteSocket`，通过一个异步互斥锁串行化所有类型化查询和关闭操作。序列号只在临界区内分配，从 1 开始，`0xffffffff` 之后回到 1，保留零值。这样可防止并发任务竞争写请求或读取彼此的数据报。

The client exposes typed Link, Address, Route, and Neighbor dump methods, plus
`get_link_by_index` and `get_link_by_name` point queries. Point queries use
`RouteSocket::request_single`: a sequence-matched `RTM_NEWLINK` completes the
request without waiting for `NLMSG_DONE`. Unexpected message types, multipart
replies and kernel rejections fail explicitly; an ACK alone is not link data.
Address and Neighbor methods perform their Link dump and object dump under the
same lock, then join interface names by ifindex. `RouteMonitor` owns a separate
multicast socket; monitor traffic is never multiplexed through this client.

客户端提供类型化 Link、Address、Route、Neighbor 导出，以及 `get_link_by_index`、`get_link_by_name` 单对象查询。单对象查询使用 `RouteSocket::request_single`，收到序列号匹配的 `RTM_NEWLINK` 即完成，不等待 `NLMSG_DONE`。意外消息类型、多部分响应和内核拒绝均明确失败；单独 ACK 不是链路数据。Address、Neighbor 方法在同一锁内执行 Link 和对象导出，按 ifindex 补齐名称。`RouteMonitor` 使用独立组播 socket，其流量不经此客户端复用。

Each query receives a configurable timeout (`5000` ms by default). Timeout
cancels the pending async `RawFd` operation and raises
`TransportError::RequestTimedOut`; non-positive timeout configuration is
rejected. The Unix event-loop implementation restores the fd read state when a
wait is cancelled. A Linux integration test deliberately sends a request whose
expected sequence cannot match, waits for timeout, and then proves that the
same socket completes a fresh dump. Any late datagrams from the timed-out
request are ignored by sequence filtering.

每次查询使用可配置超时，默认 `5000` ms。超时取消待处理的异步 `RawFd` 操作，抛出 `TransportError::RequestTimedOut`；非正数超时配置被拒绝。Unix 事件循环在等待被取消时恢复描述符读取状态。Linux 集成测试故意发送预期序列号不可能匹配的请求，等待超时后证明同一 socket 仍能完成新导出。超时请求的迟到数据报由序列号过滤忽略。

Multipart collection continues until `NLMSG_DONE`. ACK control messages are
accepted without terminating a dump, negative `NLMSG_ERROR` values become
`KernelRejected`, and unrelated sequence numbers never enter the result.
If any sequence-matched message carries `NLM_F_DUMP_INTR`, the client remembers
the interruption across datagrams, drains the response through `NLMSG_DONE`,
and raises `TransportError::DumpInterrupted` instead of returning partial state.
It does not retry automatically. Callers may issue a fresh query using the same
serialized client; draining prevents an unfinished dump from blocking it.

多部分收集持续到 `NLMSG_DONE`；ACK 不结束导出，负值 `NLMSG_ERROR` 转为 `KernelRejected`，无关序列号不进入结果。若任何匹配序列号的消息带有 `NLM_F_DUMP_INTR`，客户端跨数据报记住中断，排空响应直到 `NLMSG_DONE`，然后抛出 `TransportError::DumpInterrupted`，不返回部分状态，也不自动重试。调用者可用同一串行客户端重新查询；排空避免未结束导出阻塞下一请求。

Mutation requests use a separate ACK-only path. `request_ack` accepts success
only from a sequence-matched `NLMSG_ERROR` whose errno is zero; kernel errno,
family data, `DONE`, and other control messages fail closed. All public
mutation methods serialize this request under the same mutex and timeout
policy as queries. A timeout is an uncertain outcome: the kernel may already
have applied the change. Verify state before deciding whether to retry.

修改使用独立的仅 ACK 路径。`request_ack` 只接受序列号匹配且 errno 为零的 `NLMSG_ERROR` 作为成功；内核 errno、协议族数据、`DONE` 或其他控制消息均按失败处理。公共修改方法在与查询相同的互斥锁和超时策略下执行。超时意味着结果未确定：内核可能已完成修改。决定重试前应验证实际状态。

`.ci/validate-link-state.sh` verifies both transitions on loopback inside a
fresh user and network namespace (`unshare -Urn`). It never changes a host
interface.

`.ci/validate-link-state.sh` 在全新的用户和网络命名空间（`unshare -Urn`）内验证回环接口的两种状态转换，绝不修改宿主接口。

`.ci/validate-queries.sh` creates IPIP and veth interfaces inside a fresh user
and network namespace, runs the live point-query and socket-reuse tests, and
verifies all four CLI queries and their shared fields against `ip -j`.

`.ci/validate-queries.sh` 在全新的用户和网络命名空间创建 IPIP、veth，运行真实单对象查询与 socket 复用测试，并用 `ip -j` 核对四种 CLI 查询的共同字段。

## Kernel diagnostics / 内核诊断

The C socket shim attempts to enable `NETLINK_EXT_ACK`; unsupported socket
options do not prevent opening the socket. A rejection without diagnostic
TLVs raises `KernelRejected(errno~)`. With TLVs it raises
`KernelRejectedDetailed(errno~, original_header~, extack~)`. Both retain a
positive errno. The original header is present for `NLMSG_ERROR`, absent for
`NLMSG_DONE`; `extack` retains optional text, offset, cookie, missing fields
and unknown attributes. Malformed diagnostics raise `CodecError`.
`core.decode_extended_ack` also permits decoding success ACK warnings, while
the high-level mutation API returns `Unit` after successful acknowledgement.

C socket shim 尝试启用 `NETLINK_EXT_ACK`；不支持该选项不会阻止 socket 打开。拒绝消息没有诊断 TLV 时抛出 `KernelRejected(errno~)`，有 TLV 时抛出 `KernelRejectedDetailed(errno~, original_header~, extack~)`，均保留正值 errno。`NLMSG_ERROR` 有原始请求头，`NLMSG_DONE` 没有；`extack` 保留可选文本、偏移、cookie、缺失字段和未知属性。畸形诊断抛出 `CodecError`。`core.decode_extended_ack` 也可解码成功 ACK 的警告，而高层修改 API 在成功确认后返回 `Unit`。

## RouteMonitor / 路由事件监听器

`RouteMonitor::open()` subscribes its own socket to Link, Neighbor and
IPv4/IPv6 Address/Route groups (legacy mask 0x0555). Supply a custom `groups`
mask or receive capacity if required. Subscribe before generating changes.
`next_event` serializes readers and preserves kernel arrival order, including
multiple messages in a datagram. A complete datagram is validated before any
of its events are queued. Names in Address/Neighbor events remain unresolved;
the stream does not make extra point queries or invent state for deletions.

`RouteMonitor::open()` 为独立 socket 订阅 Link、Neighbor 和 IPv4/IPv6 Address/Route 组，旧式掩码为 0x0555；可自定义 `groups` 或接收容量。应先订阅再产生修改。`next_event` 串行化读取者，保留内核到达顺序，包括同一数据报的多条消息；只有完整数据报验证通过后才将事件入队。地址和邻居事件不解析名称，事件流不会额外执行单对象查询，也不为删除通知编造状态。

The stream propagates cancellation. Cancelling an idle read releases the
reader mutex and allows another read. `close` cancels the active read task,
closes the descriptor and clears pending events; it is synchronous and
idempotent. Pending and subsequent readers receive `ReadClosed`. Explicit
task cancellation is needed because closing RawFd alone does not wake a
suspended read in the tested async version.

事件流传播取消。取消空闲读取会释放读取者互斥锁，允许再次读取。`close` 取消活动读取任务、关闭描述符、清空待处理事件，是同步且幂等的；等待中和后续读取者收到 `ReadClosed`。在已测试的 async 版本中，仅关闭 RawFd 不会唤醒挂起读取，因此需显式取消读取任务。

`NLMSG_OVERRUN` and Linux `ENOBUFS` raise `EventStreamLost`. A full user buffer
raises `DatagramMayBeTruncated`; malformed messages retain their codec errors.
After any data-loss/decoding failure, rebuild state from fresh queries and
reopen the monitor as appropriate. Events are not a durable log; the SDK does
not claim an atomic snapshot-and-subscribe operation or silently retry gaps.

`NLMSG_OVERRUN` 和 Linux `ENOBUFS` 抛出 `EventStreamLost`；用户缓冲区填满时抛出 `DatagramMayBeTruncated`；畸形消息保留编解码错误。发生数据丢失或解码失败后，应重新查询建立状态，并按需重新打开监听器。事件不是持久日志；SDK 不承诺原子的快照加订阅操作，也不会静默重试缺口。

`.ci/validate-mutations.sh` proves the mutation and event contracts in a fresh
user/network namespace. It configures and removes IPv4/IPv6 addresses and
routes on veth, verifies MTU/UP/DOWN, rejects duplicate exclusive adds, replaces
a gateway, checks a real kernel extack, and compares live queries with `ip -j`.
Two CLI monitors verify every event family and Neighbor filtering. All child
processes are terminated in `finally`; the namespace is destroyed on exit.

`.ci/validate-mutations.sh` 在全新的用户和网络命名空间验证修改与事件约定：配置、删除 veth 的 IPv4/IPv6 地址及路由，检查 MTU/UP/DOWN，拒绝重复排他添加，替换网关，检查真实内核 extack，并用 `ip -j` 对拍实时查询。两个 CLI 监听器验证所有事件族和 Neighbor 过滤。所有子进程在 `finally` 终止，退出时销毁命名空间。
