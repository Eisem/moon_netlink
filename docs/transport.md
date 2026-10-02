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

## Concurrency

The Phase 0 socket has exactly one reader. The future `RouteClient` will
serialize requests with an async mutex, while `RouteMonitor` will own a
separate multicast socket. This prevents a request reader and event reader from
racing to consume the same datagram.
