///|
pub let nlmsg_header_length : Int = 16

///|
pub let nla_header_length : Int = 4

///|
pub let nla_f_nested : UInt16 = 0x8000

///|
pub let nla_f_net_byteorder : UInt16 = 0x4000

///|
pub let nla_type_mask : UInt16 = 0x3fff

///|
pub let nlmsg_noop : UInt16 = 1

///|
pub let nlmsg_error : UInt16 = 2

///|
pub let nlmsg_done : UInt16 = 3

///|
pub let nlmsg_overrun : UInt16 = 4

///|
/// The fixed header shared by every Netlink message.
#warnings("-implicit_impl_as_method")
pub(all) struct NetlinkHeader {
  length : UInt
  message_type : UInt16
  flags : UInt16
  sequence : UInt
  port_id : UInt
} derive(Debug, Eq)

///|
pub extend NetlinkHeader with Debug::{to_repr}

///|
pub extend NetlinkHeader with Eq::{equal, not_equal}

///|
/// One decoded message from a Netlink datagram.
#warnings("-implicit_impl_as_method")
pub(all) struct NetlinkMessage {
  header : NetlinkHeader
  payload : Bytes
} derive(Debug, Eq)

///|
pub extend NetlinkMessage with Debug::{to_repr}

///|
pub extend NetlinkMessage with Eq::{equal, not_equal}

///|
/// A decoded Netlink attribute. Unknown attribute types remain representable.
#warnings("-implicit_impl_as_method")
pub(all) struct NetlinkAttribute {
  attribute_type : UInt16
  nested : Bool
  network_byte_order : Bool
  payload : Bytes
} derive(Debug, Eq)

///|
pub extend NetlinkAttribute with Debug::{to_repr}

///|
pub extend NetlinkAttribute with Eq::{equal, not_equal}

///|
fn decode_header_at(
  data : BytesView,
  offset : Int,
) -> NetlinkHeader raise CodecError {
  require_range(data, offset, nlmsg_header_length, "netlink header")
  {
    length: read_u32_le(data, offset),
    message_type: read_u16_le(data, offset + 4),
    flags: read_u16_le(data, offset + 6),
    sequence: read_u32_le(data, offset + 8),
    port_id: read_u32_le(data, offset + 12),
  }
}

///|
/// Encode one Netlink message and normalize its wire length from the payload.
pub fn encode_message(message : NetlinkMessage) -> Bytes {
  let message_length = nlmsg_header_length + message.payload.length()
  let aligned_length = align4(message_length)
  let buffer = FixedArray::make(aligned_length, b'\x00')
  write_u32_le(buffer, 0, message_length.reinterpret_as_uint())
  write_u16_le(buffer, 4, message.header.message_type)
  write_u16_le(buffer, 6, message.header.flags)
  write_u32_le(buffer, 8, message.header.sequence)
  write_u32_le(buffer, 12, message.header.port_id)
  for index, byte in message.payload {
    buffer[nlmsg_header_length + index] = byte
  }
  Bytes::from_array(buffer[:])
}

///|
/// Encode one Netlink attribute, preserving its two standard flag bits.
pub fn encode_attribute(attribute : NetlinkAttribute) -> Bytes raise CodecError {
  let attribute_length = nla_header_length + attribute.payload.length()
  if attribute.attribute_type > nla_type_mask {
    raise InvalidAttributeType(attribute_type=attribute.attribute_type)
  }
  if attribute_length > 0xffff {
    raise LengthExceedsLimit(
      context="attribute",
      length=attribute_length,
      maximum=0xffff,
    )
  }
  let aligned_length = align4(attribute_length)
  let buffer = FixedArray::make(aligned_length, b'\x00')
  let mut raw_type = attribute.attribute_type
  if attribute.nested {
    raw_type = raw_type | nla_f_nested
  }
  if attribute.network_byte_order {
    raw_type = raw_type | nla_f_net_byteorder
  }
  write_u16_le(buffer, 0, attribute_length.to_uint16())
  write_u16_le(buffer, 2, raw_type)
  for index, byte in attribute.payload {
    buffer[nla_header_length + index] = byte
  }
  Bytes::from_array(buffer[:])
}

///|
/// Decode one or more aligned Netlink messages from a datagram.
pub fn decode_datagram(
  data : BytesView,
) -> Array[NetlinkMessage] raise CodecError {
  let messages : Array[NetlinkMessage] = []
  let mut offset = 0
  while offset < data.length() {
    let remaining = data.length() - offset
    if remaining < nlmsg_header_length {
      raise Truncated(
        context="netlink header",
        offset~,
        needed=nlmsg_header_length,
        available=remaining,
      )
    }
    let wire_length = read_u32_le(data, offset)
    if wire_length < nlmsg_header_length.reinterpret_as_uint() {
      raise InvalidLength(
        context="netlink message",
        length=wire_length,
        minimum=nlmsg_header_length,
      )
    }
    if wire_length > 0x7fff_ffff {
      raise LengthTooLarge(context="netlink message", length=wire_length)
    }
    let message_length = wire_length.reinterpret_as_int()
    if message_length > remaining {
      raise Truncated(
        context="netlink message",
        offset~,
        needed=message_length,
        available=remaining,
      )
    }
    let payload_start = offset + nlmsg_header_length
    let payload_end = offset + message_length
    messages.push({
      header: decode_header_at(data, offset),
      payload: data[payload_start:payload_end].to_owned(),
    })
    let next = offset + align4(message_length)
    if next <= offset {
      raise InvalidLength(
        context="aligned netlink message",
        length=wire_length,
        minimum=nlmsg_header_length,
      )
    }
    offset = next
  }
  messages
}

///|
/// Decode all aligned attributes in a message-specific attribute region.
pub fn decode_attributes(
  data : BytesView,
  start : Int,
) -> Array[NetlinkAttribute] raise CodecError {
  if start < 0 || start > data.length() {
    raise InvalidOffset(context="attribute region", offset=start)
  }
  let attributes : Array[NetlinkAttribute] = []
  let mut offset = start
  while offset < data.length() {
    let remaining = data.length() - offset
    if remaining < nla_header_length {
      raise Truncated(
        context="attribute header",
        offset~,
        needed=nla_header_length,
        available=remaining,
      )
    }
    let wire_length = read_u16_le(data, offset).to_uint()
    if wire_length < nla_header_length.reinterpret_as_uint() {
      raise InvalidLength(
        context="attribute",
        length=wire_length,
        minimum=nla_header_length,
      )
    }
    let attribute_length = wire_length.reinterpret_as_int()
    if attribute_length > remaining {
      raise Truncated(
        context="attribute",
        offset~,
        needed=attribute_length,
        available=remaining,
      )
    }
    let raw_type = read_u16_le(data, offset + 2)
    attributes.push({
      attribute_type: raw_type & nla_type_mask,
      nested: (raw_type & nla_f_nested) != 0,
      network_byte_order: (raw_type & nla_f_net_byteorder) != 0,
      payload: data[offset + nla_header_length:offset + attribute_length].to_owned(),
    })
    let next = offset + align4(attribute_length)
    if next <= offset {
      raise InvalidLength(
        context="aligned attribute",
        length=wire_length,
        minimum=nla_header_length,
      )
    }
    offset = next
  }
  attributes
}
