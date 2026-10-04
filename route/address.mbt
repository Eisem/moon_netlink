///|
pub let rtm_newaddr : UInt16 = 20

///|
pub let rtm_getaddr : UInt16 = 22

///|
let ifa_address : UInt16 = 1

///|
let ifa_local : UInt16 = 2

///|
let ifa_label : UInt16 = 3

///|
let ifa_flags : UInt16 = 8

///|
let af_inet : Byte = 2

///|
let af_inet6 : Byte = 10

///|
#warnings("-implicit_impl_as_method")
pub struct Ipv4Address {
  bytes : Bytes
} derive(Debug, Eq)

///|
pub extend Ipv4Address with Debug::{to_repr}

///|
pub extend Ipv4Address with Eq::{equal, not_equal}

///|
#warnings("-implicit_impl_as_method")
pub struct Ipv6Address {
  bytes : Bytes
} derive(Debug, Eq)

///|
pub extend Ipv6Address with Debug::{to_repr}

///|
pub extend Ipv6Address with Eq::{equal, not_equal}

///|
#warnings("-implicit_impl_as_method")
pub(all) enum IpAddress {
  V4(Ipv4Address)
  V6(Ipv6Address)
} derive(Debug, Eq)

///|
pub extend IpAddress with Debug::{to_repr}

///|
pub extend IpAddress with Eq::{equal, not_equal}

///|
pub fn IpAddress::to_bytes(self : IpAddress) -> Bytes {
  match self {
    V4(address) => address.bytes
    V6(address) => address.bytes
  }
}

///|
#warnings("-implicit_impl_as_method")
pub(all) enum AddressFamily {
  Ipv4
  Ipv6
  Other(Byte)
} derive(Debug, Eq)

///|
pub extend AddressFamily with Debug::{to_repr}

///|
pub extend AddressFamily with Eq::{equal, not_equal}

///|
/// One decoded RTM_NEWADDR object. `interface_name` is populated later by a
/// client-side join with Link data; the wire message contains only the index.
#warnings("-implicit_impl_as_method")
pub(all) struct Address {
  family : AddressFamily
  interface_index : UInt
  interface_name : String?
  prefix_length : Byte
  scope : Byte
  local_address : IpAddress?
  address : IpAddress?
  label : String?
  flags : UInt
  unknown_attributes : Array[@core.NetlinkAttribute]
} derive(Debug, Eq)

///|
pub extend Address with Debug::{to_repr}

///|
pub extend Address with Eq::{equal, not_equal}

///|
/// Build an RTM_GETADDR dump request for all address families.
pub fn encode_get_addresses(sequence : UInt) -> Bytes {
  let message_length = 24
  let buffer = FixedArray::make(message_length, b'\x00')
  @core.write_u32_le(buffer, 0, message_length.reinterpret_as_uint())
  @core.write_u16_le(buffer, 4, rtm_getaddr)
  @core.write_u16_le(buffer, 6, 0x0301)
  @core.write_u32_le(buffer, 8, sequence)
  @core.write_u32_le(buffer, 12, 0)
  Bytes::from_array(buffer[:])
}

///|
fn decode_address_family(value : Byte) -> AddressFamily {
  match value {
    value if value == af_inet => Ipv4
    value if value == af_inet6 => Ipv6
    other => Other(other)
  }
}

///|
fn decode_ip_address(
  family : AddressFamily,
  attribute : @core.NetlinkAttribute,
  context : String,
) -> IpAddress? raise @core.CodecError {
  match family {
    Ipv4 => {
      require_attribute_length(attribute, 4, context)
      Some(V4({ bytes: attribute.payload, }))
    }
    Ipv6 => {
      require_attribute_length(attribute, 16, context)
      Some(V6({ bytes: attribute.payload, }))
    }
    Other(_) => None
  }
}

///|
pub fn decode_address(
  message : @core.NetlinkMessage,
) -> Address raise @core.CodecError {
  let payload = message.payload[:]
  if payload.length() < 8 {
    raise Truncated(
      context="ifaddrmsg",
      offset=0,
      needed=8,
      available=payload.length(),
    )
  }
  let family = decode_address_family(payload[0])
  let attributes = @core.decode_attributes(payload, 8)
  let mut local_address : IpAddress? = None
  let mut address : IpAddress? = None
  let mut label : String? = None
  let mut flags = payload[2].to_uint()
  let unknown : Array[@core.NetlinkAttribute] = []
  for attribute in attributes {
    if attribute.attribute_type == ifa_local {
      local_address = decode_ip_address(family, attribute, "IFA_LOCAL")
      if family is Other(_) {
        unknown.push(attribute)
      }
    } else if attribute.attribute_type == ifa_address {
      address = decode_ip_address(family, attribute, "IFA_ADDRESS")
      if family is Other(_) {
        unknown.push(attribute)
      }
    } else if attribute.attribute_type == ifa_label {
      label = Some(decode_nul_string(attribute.payload, "IFA_LABEL"))
    } else if attribute.attribute_type == ifa_flags {
      require_attribute_length(attribute, 4, "IFA_FLAGS")
      flags = @core.read_u32_le(attribute.payload, 0)
    } else {
      unknown.push(attribute)
    }
  }
  {
    family,
    interface_index: @core.read_u32_le(payload, 4),
    interface_name: None,
    prefix_length: payload[1],
    scope: payload[3],
    local_address,
    address,
    label,
    flags,
    unknown_attributes: unknown,
  }
}

///|
pub fn decode_addresses(
  messages : ArrayView[@core.NetlinkMessage],
) -> Array[Address] raise @core.CodecError {
  let addresses : Array[Address] = []
  for message in messages {
    if message.header.message_type == rtm_newaddr {
      addresses.push(decode_address(message))
    }
  }
  addresses
}
