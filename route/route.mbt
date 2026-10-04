///|
pub let rtm_newroute : UInt16 = 24

///|
pub let rtm_getroute : UInt16 = 26

///|
let rta_destination : UInt16 = 1

///|
let rta_source : UInt16 = 2

///|
let rta_input_interface : UInt16 = 3

///|
let rta_output_interface : UInt16 = 4

///|
let rta_gateway : UInt16 = 5

///|
let rta_priority : UInt16 = 6

///|
let rta_preferred_source : UInt16 = 7

///|
let rta_table : UInt16 = 15

///|
/// One decoded RTM_NEWROUTE object. Interface names are resolved later by
/// joining the numeric indices with Link data in `RouteClient`.
#warnings("-implicit_impl_as_method")
pub(all) struct Route {
  family : AddressFamily
  destination : IpAddress?
  destination_prefix_length : Byte
  source : IpAddress?
  source_prefix_length : Byte
  gateway : IpAddress?
  preferred_source : IpAddress?
  input_interface : UInt?
  output_interface : UInt?
  table : UInt
  priority : UInt?
  protocol : Byte
  scope : Byte
  route_type : Byte
  tos : Byte
  flags : UInt
  unknown_attributes : Array[@core.NetlinkAttribute]
} derive(Debug, Eq)

///|
pub extend Route with Debug::{to_repr}

///|
pub extend Route with Eq::{equal, not_equal}

///|
/// Build an RTM_GETROUTE dump request for all address families and tables.
pub fn encode_get_routes(sequence : UInt) -> Bytes {
  let message_length = 28
  let buffer = FixedArray::make(message_length, b'\x00')
  @core.write_u32_le(buffer, 0, message_length.reinterpret_as_uint())
  @core.write_u16_le(buffer, 4, rtm_getroute)
  @core.write_u16_le(buffer, 6, 0x0301)
  @core.write_u32_le(buffer, 8, sequence)
  @core.write_u32_le(buffer, 12, 0)
  Bytes::from_array(buffer[:])
}

///|
fn decode_route_ip(
  family : AddressFamily,
  attribute : @core.NetlinkAttribute,
  context : String,
  unknown : Array[@core.NetlinkAttribute],
) -> IpAddress? raise @core.CodecError {
  let value = decode_ip_address(family, attribute, context)
  if family is Other(_) {
    unknown.push(attribute)
  }
  value
}

///|
fn decode_route_u32(
  attribute : @core.NetlinkAttribute,
  context : String,
) -> UInt raise @core.CodecError {
  require_attribute_length(attribute, 4, context)
  @core.read_u32_le(attribute.payload, 0)
}

///|
pub fn decode_route(
  message : @core.NetlinkMessage,
) -> Route raise @core.CodecError {
  let payload = message.payload[:]
  if payload.length() < 12 {
    raise Truncated(
      context="rtmsg",
      offset=0,
      needed=12,
      available=payload.length(),
    )
  }
  let family = decode_address_family(payload[0])
  let attributes = @core.decode_attributes(payload, 12)
  let mut destination : IpAddress? = None
  let mut source : IpAddress? = None
  let mut gateway : IpAddress? = None
  let mut preferred_source : IpAddress? = None
  let mut input_interface : UInt? = None
  let mut output_interface : UInt? = None
  let mut table = payload[4].to_uint()
  let mut priority : UInt? = None
  let unknown : Array[@core.NetlinkAttribute] = []
  for attribute in attributes {
    if attribute.attribute_type == rta_destination {
      destination = decode_route_ip(family, attribute, "RTA_DST", unknown)
    } else if attribute.attribute_type == rta_source {
      source = decode_route_ip(family, attribute, "RTA_SRC", unknown)
    } else if attribute.attribute_type == rta_gateway {
      gateway = decode_route_ip(family, attribute, "RTA_GATEWAY", unknown)
    } else if attribute.attribute_type == rta_preferred_source {
      preferred_source = decode_route_ip(
        family, attribute, "RTA_PREFSRC", unknown,
      )
    } else if attribute.attribute_type == rta_input_interface {
      input_interface = Some(decode_route_u32(attribute, "RTA_IIF"))
    } else if attribute.attribute_type == rta_output_interface {
      output_interface = Some(decode_route_u32(attribute, "RTA_OIF"))
    } else if attribute.attribute_type == rta_table {
      table = decode_route_u32(attribute, "RTA_TABLE")
    } else if attribute.attribute_type == rta_priority {
      priority = Some(decode_route_u32(attribute, "RTA_PRIORITY"))
    } else {
      unknown.push(attribute)
    }
  }
  {
    family,
    destination,
    destination_prefix_length: payload[1],
    source,
    source_prefix_length: payload[2],
    gateway,
    preferred_source,
    input_interface,
    output_interface,
    table,
    priority,
    protocol: payload[5],
    scope: payload[6],
    route_type: payload[7],
    tos: payload[3],
    flags: @core.read_u32_le(payload, 8),
    unknown_attributes: unknown,
  }
}

///|
pub fn decode_routes(
  messages : ArrayView[@core.NetlinkMessage],
) -> Array[Route] raise @core.CodecError {
  let routes : Array[Route] = []
  for message in messages {
    if message.header.message_type == rtm_newroute {
      routes.push(decode_route(message))
    }
  }
  routes
}
