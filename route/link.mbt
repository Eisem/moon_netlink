///|
pub let rtm_newlink : UInt16 = 16

///|
pub let rtm_getlink : UInt16 = 18

///|
let nlm_f_request : UInt16 = 0x0001

///|
let nlm_f_ack : UInt16 = 0x0004

///|
let nlm_f_dump : UInt16 = 0x0300

///|
let iff_up : UInt = 0x0001

///|
let ifla_ifname : UInt16 = 3

///|
let ifla_address : UInt16 = 1

///|
let ifla_mtu : UInt16 = 4

///|
let ifla_master : UInt16 = 10

///|
let ifla_operstate : UInt16 = 16

///|
let ifla_linkinfo : UInt16 = 18

///|
let ifla_info_kind : UInt16 = 1

///|
/// A validated six-byte Ethernet MAC address.
#warnings("-implicit_impl_as_method")
pub struct MacAddress {
  bytes : Bytes
} derive(Debug, Eq)

///|
pub extend MacAddress with Debug::{to_repr}

///|
pub extend MacAddress with Eq::{equal, not_equal}

///|
pub fn MacAddress::to_bytes(self : MacAddress) -> Bytes {
  self.bytes
}

///|
pub fn MacAddress::to_string(self : MacAddress) -> String {
  let digits : FixedArray[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let output = StringBuilder()
  for index, byte in self.bytes {
    if index > 0 {
      output.write_char(':')
    }
    let value = byte.to_int()
    output.write_char(digits[value >> 4])
    output.write_char(digits[value & 0x0f])
  }
  output.to_string()
}

///|
#warnings("-implicit_impl_as_method")
pub(all) enum LinkOperationalState {
  Unknown
  NotPresent
  Down
  LowerLayerDown
  Testing
  Dormant
  Up
  Other(Byte)
} derive(Debug, Eq)

///|
pub extend LinkOperationalState with Debug::{to_repr}

///|
pub extend LinkOperationalState with Eq::{equal, not_equal}

///|
/// The first typed RTNetlink model used by the feasibility probe.
#warnings("-implicit_impl_as_method")
pub(all) struct Link {
  index : Int
  name : String?
  kind : String?
  mtu : UInt?
  mac : MacAddress?
  flags : UInt
  operational_state : LinkOperationalState?
  master_index : Int?
  unknown_attributes : Array[@core.NetlinkAttribute]
} derive(Debug, Eq)

///|
pub extend Link with Debug::{to_repr}

///|
pub extend Link with Eq::{equal, not_equal}

///|
/// Build an RTM_GETLINK dump request for a caller-provided sequence number.
pub fn encode_get_links(sequence : UInt) -> Bytes {
  encode_get_link_request(sequence, nlm_f_request | nlm_f_dump, 0, b"")
}

///|
/// Build an acknowledged `RTM_NEWLINK` request that changes only `IFF_UP`.
///
/// Passing `true` requests the administratively-up state; passing `false`
/// requests the administratively-down state. All other interface flags are
/// left unchanged through `ifi_change`.
pub fn encode_set_link_state(
  sequence : UInt,
  index : Int,
  up : Bool,
) -> Bytes raise LinkQueryError {
  if index <= 0 {
    raise InvalidInterfaceIndex(index~)
  }
  let message_length = 32
  let buffer = FixedArray::make(message_length, b'\x00')
  @core.write_u32_le(buffer, 0, message_length.reinterpret_as_uint())
  @core.write_u16_le(buffer, 4, rtm_newlink)
  @core.write_u16_le(buffer, 6, nlm_f_request | nlm_f_ack)
  @core.write_u32_le(buffer, 8, sequence)
  @core.write_u32_le(buffer, 12, 0)
  // ifinfomsg starts at offset 16. Only IFF_UP participates in the change.
  @core.write_u32_le(buffer, 20, index.reinterpret_as_uint())
  @core.write_u32_le(buffer, 24, if up { iff_up } else { 0 })
  @core.write_u32_le(buffer, 28, iff_up)
  Bytes::from_array(buffer[:])
}

///|
fn encode_get_link_request(
  sequence : UInt,
  flags : UInt16,
  index : Int,
  attributes : Bytes,
) -> Bytes {
  let message_length = 32 + attributes.length()
  let buffer = FixedArray::make(message_length, b'\x00')
  @core.write_u32_le(buffer, 0, message_length.reinterpret_as_uint())
  @core.write_u16_le(buffer, 4, rtm_getlink)
  @core.write_u16_le(buffer, 6, flags)
  @core.write_u32_le(buffer, 8, sequence)
  @core.write_u32_le(buffer, 12, 0)
  // ifinfomsg starts at offset 16. AF_UNSPEC and unspecified fields are zero.
  @core.write_u32_le(buffer, 20, index.reinterpret_as_uint())
  for attribute_index, byte in attributes {
    buffer[32 + attribute_index] = byte
  }
  Bytes::from_array(buffer[:])
}

///|
/// Build an RTM_GETLINK point query for a positive interface index.
pub fn encode_get_link_by_index(
  sequence : UInt,
  index : Int,
) -> Bytes raise LinkQueryError {
  if index <= 0 {
    raise InvalidInterfaceIndex(index~)
  }
  encode_get_link_request(sequence, nlm_f_request, index, b"")
}

///|
fn is_well_formed_utf16(value : String) -> Bool {
  for index = 0; index < value.length(); {
    let unit = value[index].to_int()
    if unit >= 0xd800 && unit <= 0xdbff {
      if index + 1 >= value.length() {
        break false
      }
      let next = value[index + 1].to_int()
      if next < 0xdc00 || next > 0xdfff {
        break false
      }
      continue index + 2
    } else if unit >= 0xdc00 && unit <= 0xdfff {
      break false
    } else {
      continue index + 1
    }
  } nobreak {
    true
  }
}

///|
/// Build an RTM_GETLINK point query for a validated Linux interface name.
///
/// Linux `IFNAMSIZ` is 16 bytes including the terminating NUL, so the encoded
/// name may contain at most 15 UTF-8 bytes.
pub fn encode_get_link_by_name(
  sequence : UInt,
  name : String,
) -> Bytes raise LinkQueryError {
  if name.length() == 0 {
    raise EmptyInterfaceName
  }
  if name.contains_code_unit(0) {
    raise InterfaceNameContainsNul
  }
  if !is_well_formed_utf16(name) {
    raise InterfaceNameInvalidUtf16
  }
  let encoded = @utf8.encode(name)
  if encoded.length() > 15 {
    raise InterfaceNameTooLong(encoded_length=encoded.length(), maximum=15)
  }
  let attribute_length = @core.nla_header_length + encoded.length() + 1
  let buffer = FixedArray::make(@core.align4(attribute_length), b'\x00')
  @core.write_u16_le(buffer, 0, attribute_length.to_uint16())
  @core.write_u16_le(buffer, 2, ifla_ifname)
  for index, byte in encoded {
    buffer[@core.nla_header_length + index] = byte
  }
  encode_get_link_request(
    sequence,
    nlm_f_request,
    0,
    Bytes::from_array(buffer[:]),
  )
}

///|
fn decode_nul_string(
  payload : BytesView,
  context : String,
) -> String raise @core.CodecError {
  if payload.length() == 0 || payload[payload.length() - 1] != b'\x00' {
    raise InvalidString(context~)
  }
  for index in 0..<(payload.length() - 1) {
    if payload[index] == b'\x00' {
      raise InvalidString(context~)
    }
  }
  @utf8.decode(payload[:payload.length() - 1]) catch {
    Malformed(_) => raise InvalidString(context~)
  }
}

///|
fn require_attribute_length(
  attribute : @core.NetlinkAttribute,
  expected : Int,
  context : String,
) -> Unit raise @core.CodecError {
  if attribute.payload.length() != expected {
    raise UnexpectedFieldLength(
      context~,
      length=attribute.payload.length(),
      expected~,
    )
  }
}

///|
fn decode_mac(
  attribute : @core.NetlinkAttribute,
) -> MacAddress raise @core.CodecError {
  require_attribute_length(attribute, 6, "IFLA_ADDRESS")
  { bytes: attribute.payload, }
}

///|
fn decode_operstate(
  attribute : @core.NetlinkAttribute,
) -> LinkOperationalState raise @core.CodecError {
  require_attribute_length(attribute, 1, "IFLA_OPERSTATE")
  match attribute.payload[0] {
    0 => Unknown
    1 => NotPresent
    2 => Down
    3 => LowerLayerDown
    4 => Testing
    5 => Dormant
    6 => Up
    value => Other(value)
  }
}

///|
fn decode_link_kind(
  attribute : @core.NetlinkAttribute,
) -> String? raise @core.CodecError {
  let nested = @core.decode_attributes(attribute.payload, 0)
  for item in nested {
    if item.attribute_type == ifla_info_kind {
      return Some(decode_nul_string(item.payload, "IFLA_INFO_KIND"))
    }
  }
  None
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
  let hardware_type = @core.read_u16_le(payload, 2)
  let mut name : String? = None
  let mut kind : String? = None
  let mut mtu : UInt? = None
  let mut mac : MacAddress? = None
  let mut operational_state : LinkOperationalState? = None
  let mut master_index : Int? = None
  let unknown : Array[@core.NetlinkAttribute] = []
  for attribute in attributes {
    if attribute.attribute_type == ifla_ifname {
      name = Some(decode_nul_string(attribute.payload, "IFLA_IFNAME"))
    } else if attribute.attribute_type == ifla_address {
      // ARPHRD_ETHER and ARPHRD_LOOPBACK carry six-byte addresses. Tunnel,
      // InfiniBand and other link types use different hardware addresses.
      if hardware_type == 1 || hardware_type == 772 {
        mac = Some(decode_mac(attribute))
      } else {
        unknown.push(attribute)
      }
    } else if attribute.attribute_type == ifla_mtu {
      require_attribute_length(attribute, 4, "IFLA_MTU")
      mtu = Some(@core.read_u32_le(attribute.payload, 0))
    } else if attribute.attribute_type == ifla_master {
      require_attribute_length(attribute, 4, "IFLA_MASTER")
      master_index = Some(@core.read_i32_le(attribute.payload, 0))
    } else if attribute.attribute_type == ifla_operstate {
      operational_state = Some(decode_operstate(attribute))
    } else if attribute.attribute_type == ifla_linkinfo {
      kind = decode_link_kind(attribute)
      // Preserve the complete container until nested unknown attributes have
      // their own public representation.
      unknown.push(attribute)
    } else {
      unknown.push(attribute)
    }
  }
  {
    index: @core.read_i32_le(payload, 4),
    name,
    kind,
    mtu,
    mac,
    flags: @core.read_u32_le(payload, 8),
    operational_state,
    master_index,
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
