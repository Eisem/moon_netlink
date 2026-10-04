# Core codec contract

The `core` package owns the transport-independent Netlink wire format. It has
no socket dependency and can be tested on any native host supported by this
module.

## Messages and alignment

`decode_datagram` validates each 16-byte Netlink header before reading its
payload. A message length smaller than the header, larger than the remaining
datagram, or too large for MoonBit's signed indexing produces a structured
`CodecError`. Multipart datagrams advance by four-byte `NLMSG_ALIGN` boundaries;
a zero or invalid length cannot stall the parser.

`encode_message` derives `nlmsg_len` from the owned payload rather than trusting
the caller's header length. It emits zero-filled alignment bytes. Decoding and
re-encoding therefore preserves message semantics, but deliberately normalizes
padding and length fields.

## Attributes

`decode_attributes` separates the base attribute type from Linux's
`NLA_F_NESTED` and `NLA_F_NET_BYTEORDER` bits. Unknown base types remain ordinary
`NetlinkAttribute` values with their payload bytes intact. `encode_attribute`
reconstructs both flag bits, zero-fills alignment padding, and rejects a value
that cannot fit the 16-bit `nla_len` field.

## Generic control messages

`decode_control` distinguishes family messages from `NLMSG_NOOP`, `NLMSG_DONE`,
`NLMSG_ERROR`, and `NLMSG_OVERRUN`. An `NLMSG_ERROR` payload with errno zero is
an `Ack`; a nonzero errno is normalized to a positive `KernelError` code while
retaining the embedded request header. Malformed control payloads return
`CodecError` rather than panicking.

The transport waits for `Done` to finish a dump. Receiving an `Ack` alone no
longer ends a multipart request, and a nonzero `Done` status is surfaced as a
kernel rejection.

## Extended acknowledgements

`decode_extended_ack` returns `None` unless `NLM_F_ACK_TLVS` is set. For
`NLMSG_ERROR`, it skips the embedded header and, for uncapped failures, the
aligned echoed request body. Success ACKs and `NLM_F_CAPPED` errors do not
echo that body. `NLMSG_DONE` diagnostics begin after the four-byte status.
Every offset and attribute length is checked before access.

`ExtendedAck` exposes message text, offending offset, cookie, missing
attribute type/nesting offset, and unknown attributes. Text requires valid
UTF-8 and a single terminal NUL; integer attributes require exactly four
bytes. Unknown attributes and opaque cookies retain their bytes. The existing
`NetlinkControl` API remains compatible; extended diagnostics are a separate
decoder. Layout follows the official Linux
[Netlink introduction](https://docs.kernel.org/userspace-api/netlink/intro.html).
