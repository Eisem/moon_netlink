///|
/// Kernel diagnostics carried by NLMSG_ERROR or NLMSG_DONE with ACK_TLVS.
#warnings("-implicit_impl_as_method")
pub(all) struct ExtendedAck {
  message : String?
  offset : UInt?
  cookie : Bytes?
  missing_type : UInt?
  missing_nest : UInt?
  unknown_attributes : Array[NetlinkAttribute]
} derive(Debug, Eq)

///|
pub extend ExtendedAck with Debug::{to_repr}

///|
pub extend ExtendedAck with Eq::{equal, not_equal}

///|
/// Decode capped/uncapped error TLVs, success warnings and DONE diagnostics.
/// The echoed request body is skipped only when it is present; unknown TLVs
/// are retained. Missing ACK_TLVS returns None without guessing at payloads.
pub fn decode_extended_ack(
  message : NetlinkMessage,
) -> ExtendedAck? raise CodecError {
  if (message.header.flags & 0x0200) == 0 {
    return None
  }
  let start = if message.header.message_type == nlmsg_error {
    let errno = read_i32_le(message.payload, 0)
    let original = decode_embedded_header(message.payload)
    if errno == 0 || (message.header.flags & 0x0100) != 0 {
      20
    } else {
      let available = message.payload.length() - 4
      if original.length > available.reinterpret_as_uint() {
        raise Truncated(
          context="nlmsgerr echoed request",
          offset=4,
          needed=if original.length > 0x7fff_ffff {
            0x7fff_ffff
          } else {
            original.length.reinterpret_as_int()
          },
          available~,
        )
      }
      4 + align4(original.length.reinterpret_as_int())
    }
  } else if message.header.message_type == nlmsg_done {
    require_range(message.payload, 0, 4, "NLMSG_DONE status")
    4
  } else {
    return None
  }
  if start > message.payload.length() {
    raise Truncated(
      context="extack attributes",
      offset=start,
      needed=0,
      available=0,
    )
  }
  let attributes = decode_attributes(message.payload, start)
  let mut text : String? = None
  let mut offset : UInt? = None
  let mut cookie : Bytes? = None
  let mut missing_type : UInt? = None
  let mut missing_nest : UInt? = None
  let unknown : Array[NetlinkAttribute] = []
  for attribute in attributes {
    match attribute.attribute_type {
      1 => {
        let bytes = attribute.payload
        if bytes.length() == 0 || bytes[bytes.length() - 1] != 0 {
          raise InvalidString(context="NLMSGERR_ATTR_MSG")
        }
        for byte in bytes[:bytes.length() - 1] {
          if byte == 0 {
            raise InvalidString(context="NLMSGERR_ATTR_MSG")
          }
        }
        text = Some(
          @utf8.decode(bytes[:bytes.length() - 1]) catch {
            Malformed(_) => raise InvalidString(context="NLMSGERR_ATTR_MSG")
          },
        )
      }
      2 | 5 | 6 => {
        if attribute.payload.length() != 4 {
          raise UnexpectedFieldLength(
            context="extack u32",
            length=attribute.payload.length(),
            expected=4,
          )
        }
        let value = read_u32_le(attribute.payload, 0)
        match attribute.attribute_type {
          2 => offset = Some(value)
          5 => missing_type = Some(value)
          _ => missing_nest = Some(value)
        }
      }
      3 => cookie = Some(attribute.payload)
      _ => unknown.push(attribute)
    }
  }
  Some({
    message: text,
    offset,
    cookie,
    missing_type,
    missing_nest,
    unknown_attributes: unknown,
  })
}
