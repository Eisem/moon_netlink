///|
/// A decoded generic Netlink control message.
#warnings("-implicit_impl_as_method")
pub(all) enum NetlinkControl {
  Noop
  Done(Int?)
  Ack(NetlinkHeader)
  KernelError(Int, NetlinkHeader)
  Overrun
} derive(Debug, Eq)

///|
pub extend NetlinkControl with Debug::{to_repr}

///|
pub extend NetlinkControl with Eq::{equal, not_equal}

///|
fn decode_embedded_header(
  payload : BytesView,
) -> NetlinkHeader raise CodecError {
  if payload.length() < 4 + nlmsg_header_length {
    raise Truncated(
      context="nlmsgerr",
      offset=0,
      needed=4 + nlmsg_header_length,
      available=payload.length(),
    )
  }
  let header = decode_header_at(payload, 4)
  if header.length < nlmsg_header_length.reinterpret_as_uint() {
    raise InvalidLength(
      context="nlmsgerr original message",
      length=header.length,
      minimum=nlmsg_header_length,
    )
  }
  header
}

///|
/// Decode a generic control message, or return `None` for a family message.
///
/// `NLMSG_ERROR` with errno zero is an acknowledgement, not a failure. Kernel
/// errno values are returned as positive numbers for user-facing reporting.
pub fn decode_control(
  message : NetlinkMessage,
) -> NetlinkControl? raise CodecError {
  match message.header.message_type {
    message_type if message_type == nlmsg_noop => Some(Noop)
    message_type if message_type == nlmsg_done => {
      let status = if message.payload.length() == 0 {
        None
      } else {
        Some(read_i32_le(message.payload, 0))
      }
      Some(Done(status))
    }
    message_type if message_type == nlmsg_error => {
      let errno = read_i32_le(message.payload, 0)
      let original_header = decode_embedded_header(message.payload)
      if errno == 0 {
        Some(Ack(original_header))
      } else {
        Some(
          KernelError(if errno < 0 { -errno } else { errno }, original_header),
        )
      }
    }
    message_type if message_type == nlmsg_overrun => Some(Overrun)
    _ => None
  }
}
