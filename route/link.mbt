///|
pub let rtm_newlink : UInt16 = 16

///|
pub let rtm_getlink : UInt16 = 18

///|
let nlm_f_request : UInt16 = 0x0001

///|
let nlm_f_dump : UInt16 = 0x0300

///|
let ifla_ifname : UInt16 = 3

///|
/// The first typed RTNetlink model used by the feasibility probe.
#warnings("-implicit_impl_as_method")
pub(all) struct Link {
  index : Int
  name : String?
  flags : UInt
  unknown_attributes : Array[@core.NetlinkAttribute]
} derive(Debug, Eq)

///|
pub extend Link with Debug::{to_repr}

///|
pub extend Link with Eq::{equal, not_equal}

///|
/// Build an RTM_GETLINK dump request for a caller-provided sequence number.
pub fn encode_get_links(sequence : UInt) -> Bytes {
  let message_length = 32
  let buffer = FixedArray::make(message_length, b'\x00')
  @core.write_u32_le(buffer, 0, message_length.reinterpret_as_uint())
  @core.write_u16_le(buffer, 4, rtm_getlink)
  @core.write_u16_le(buffer, 6, nlm_f_request | nlm_f_dump)
  @core.write_u32_le(buffer, 8, sequence)
  @core.write_u32_le(buffer, 12, 0)
  // ifinfomsg starts at offset 16. AF_UNSPEC and all remaining fields are zero.
  Bytes::from_array(buffer[:])
}

///|
fn decode_ifname(payload : BytesView) -> String {
  let mut end = 0
  while end < payload.length() && payload[end] != b'\x00' {
    end += 1
  }
  @utf8.decode_lossy(payload[:end])
}

///|
/// Decode one RTM_NEWLINK body, preserving attributes not yet modeled.
pub fn decode_link(
  message : @core.NetlinkMessage,
) -> Link raise @core.CodecError {
  let payload = message.payload[:]
  if payload.length() < 16 {
    raise Truncated(
      context="ifinfomsg",
      offset=0,
      needed=16,
      available=payload.length(),
    )
  }
  let attributes = @core.decode_attributes(payload, 16)
  let mut name : String? = None
  let unknown : Array[@core.NetlinkAttribute] = []
  for attribute in attributes {
    if attribute.attribute_type == ifla_ifname {
      name = Some(decode_ifname(attribute.payload))
    } else {
      unknown.push(attribute)
    }
  }
  {
    index: @core.read_i32_le(payload, 4),
    name,
    flags: @core.read_u32_le(payload, 8),
    unknown_attributes: unknown,
  }
}

///|
/// Decode only RTM_NEWLINK messages from a completed dump.
pub fn decode_links(
  messages : ArrayView[@core.NetlinkMessage],
) -> Array[Link] raise @core.CodecError {
  let links : Array[Link] = []
  for message in messages {
    if message.header.message_type == rtm_newlink {
      links.push(decode_link(message))
    }
  }
  links
}
