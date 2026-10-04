# Transport ownership and datagram contract

This document records the Phase 0 transport decisions that are not obvious
from the public API.

## Descriptor ownership

`native_open_route_socket` initially returns a small native owner object. Its
finalizer closes the descriptor unless `take_fd` transfers it to
`moonbitlang/async/raw_fd.RawFd`. After transfer, only `RawFd` owns and closes
the descriptor. `RouteSocket::close` is idempotent.

The ownership transfer applies even when `RawFd` registration raises an error;
this follows the `RawFd` contract and prevents a second close in MoonNetlink.

## Datagram reads

`NETLINK_ROUTE` uses datagram semantics. One `RawFd::read` performs one
`read(2)` call and consumes one queued Netlink datagram. If the user buffer is
too small, Linux copies only the prefix and discards the remainder of that
datagram.

The current public `RawFd` API does not expose `recvmsg(2)`, `MSG_TRUNC`, or a
readiness-only wait. Consequently MoonNetlink cannot safely peek the exact
datagram size and then retry without building a larger event-loop integration.

The Phase 0 policy is therefore:

1. use a 256 KiB receive buffer by default;
2. allow callers to configure the capacity when opening `RouteSocket`;
3. reject capacities smaller than a Netlink header;
4. if `read` returns exactly the buffer capacity, raise
   `DatagramMayBeTruncated` and discard the whole request result;
5. never feed a potentially truncated datagram into the protocol decoder.

An exact-size datagram produces a conservative false positive. This is
intentional: a false failure is safer than silently accepting incomplete
kernel state. Multipart dumps may span any number of datagrams; the capacity
limits each individual datagram, not the total dump size.

The Linux-only white-box test `live Netlink datagram truncation fails closed`
opens a real route socket with a deliberately 16-byte capacity and verifies
that an `RTM_GETLINK` response raises `DatagramMayBeTruncated` before decoding.

If real workloads exceed this limit frequently, a future transport may add a
minimal `recvmsg(MSG_PEEK | MSG_TRUNC)` integration. It must preserve async
cancellation and single-reader guarantees before replacing this policy.

## Datagram writes

Each Netlink request is passed to one `RawFd::write` call. A short write raises
`ShortWrite`; MoonNetlink never sends the remainder as a second datagram.

## RouteClient and concurrency

`RouteClient` owns exactly one `RouteSocket` and serializes every typed query
and close operation with one async mutex. Sequence numbers are allocated only
inside that critical section, start at one, and wrap from `0xffffffff` back to
one so zero remains reserved. This prevents concurrent tasks from racing to
write requests or consume each other's datagrams.

The client exposes typed Link, Address, Route, and Neighbor dump methods, plus
`get_link_by_index` and `get_link_by_name` point queries. Point queries use
`RouteSocket::request_single`: a sequence-matched `RTM_NEWLINK` completes the
request without waiting for `NLMSG_DONE`. Unexpected message types, multipart
replies and kernel rejections fail explicitly; an ACK alone is not link data.
Address and Neighbor methods perform their Link dump and object dump under the
same lock, then join interface names by ifindex. `RouteMonitor` owns a separate
multicast socket; monitor traffic is never multiplexed through this client.

Each query receives a configurable timeout (`5000` ms by default). Timeout
cancels the pending async `RawFd` operation and raises
`TransportError::RequestTimedOut`; non-positive timeout configuration is
rejected. The Unix event-loop implementation restores the fd read state when a
wait is cancelled. A Linux integration test deliberately sends a request whose
expected sequence cannot match, waits for timeout, and then proves that the
same socket completes a fresh dump. Any late datagrams from the timed-out
request are ignored by sequence filtering.

Multipart collection continues until `NLMSG_DONE`. ACK control messages are
accepted without terminating a dump, negative `NLMSG_ERROR` values become
`KernelRejected`, and unrelated sequence numbers never enter the result.
If any sequence-matched message carries `NLM_F_DUMP_INTR`, the client remembers
the interruption across datagrams, drains the response through `NLMSG_DONE`,
and raises `TransportError::DumpInterrupted` instead of returning partial state.
It does not retry automatically. Callers may issue a fresh query using the same
serialized client; draining prevents an unfinished dump from blocking it.

Mutation requests use a separate ACK-only path. `request_ack` accepts success
only from a sequence-matched `NLMSG_ERROR` whose errno is zero; kernel errno,
family data, `DONE`, and other control messages fail closed. All public
mutation methods serialize this request under the same mutex and timeout
policy as queries. A timeout is an uncertain outcome: the kernel may already
have applied the change. Verify state before deciding whether to retry.

`.ci/validate-link-state.sh` verifies both transitions on loopback inside a
fresh user and network namespace (`unshare -Urn`). It never changes a host
interface.

`.ci/validate-queries.sh` creates IPIP and veth interfaces inside a fresh user
and network namespace, runs the live point-query and socket-reuse tests, and
verifies all four CLI queries and their shared fields against `ip -j`.

## Kernel diagnostics

The C socket shim attempts to enable `NETLINK_EXT_ACK`; unsupported socket
options do not prevent opening the socket. A rejection without diagnostic
TLVs raises `KernelRejected(errno~)`. With TLVs it raises
`KernelRejectedDetailed(errno~, original_header~, extack~)`. Both retain a
positive errno. The original header is present for `NLMSG_ERROR`, absent for
`NLMSG_DONE`; `extack` retains optional text, offset, cookie, missing fields
and unknown attributes. Malformed diagnostics raise `CodecError`.
`core.decode_extended_ack` also permits decoding success ACK warnings, while
the high-level mutation API returns `Unit` after successful acknowledgement.

## RouteMonitor

`RouteMonitor::open()` subscribes its own socket to Link, Neighbor and
IPv4/IPv6 Address/Route groups (legacy mask 0x0555). Supply a custom `groups`
mask or receive capacity if required. Subscribe before generating changes.
`next_event` serializes readers and preserves kernel arrival order, including
multiple messages in a datagram. A complete datagram is validated before any
of its events are queued. Names in Address/Neighbor events remain unresolved;
the stream does not make extra point queries or invent state for deletions.

The stream propagates cancellation. Cancelling an idle read releases the
reader mutex and allows another read. `close` cancels the active read task,
closes the descriptor and clears pending events; it is synchronous and
idempotent. Pending and subsequent readers receive `ReadClosed`. Explicit
task cancellation is needed because closing RawFd alone does not wake a
suspended read in the tested async version.

`NLMSG_OVERRUN` and Linux `ENOBUFS` raise `EventStreamLost`. A full user buffer
raises `DatagramMayBeTruncated`; malformed messages retain their codec errors.
After any data-loss/decoding failure, rebuild state from fresh queries and
reopen the monitor as appropriate. Events are not a durable log; the SDK does
not claim an atomic snapshot-and-subscribe operation or silently retry gaps.

`.ci/validate-mutations.sh` proves the mutation and event contracts in a fresh
user/network namespace. It configures and removes IPv4/IPv6 addresses and
routes on veth, verifies MTU/UP/DOWN, rejects duplicate exclusive adds, replaces
a gateway, checks a real kernel extack, and compares live queries with `ip -j`.
Two CLI monitors verify every event family and Neighbor filtering. All child
processes are terminated in `finally`; the namespace is destroyed on exit.
