///|
/// Exclusive creation fails if the resource exists; replacement creates or
/// replaces it. Neither mode appends duplicate entries implicitly.
#warnings("-implicit_impl_as_method")
pub(all) enum AddMode {
  Exclusive
  Replace
} derive(Debug, Eq)

///|
pub extend AddMode with Debug::{to_repr}

///|
pub extend AddMode with Eq::{equal, not_equal}

///|
pub extend AddressSpec with Debug::{to_repr}

///|
pub extend AddressSpec with Eq::{equal, not_equal}

///|
pub extend RouteSpec with Debug::{to_repr}

///|
pub extend RouteSpec with Eq::{equal, not_equal}

///|
pub extend MutationError with Debug::{to_repr}

///|
pub extend MutationError with Eq::{equal, not_equal}

///|
/// One local IPv4/IPv6 address to add or delete on an existing interface.
#warnings("-implicit_impl_as_method")
pub(all) struct AddressSpec {
  interface_index : Int
  address : IpAddress
  prefix_length : Byte
  scope : Byte
} derive(Debug, Eq)

///|
/// A unicast route with an explicit family (from destination), canonical
/// destination prefix, output interface and numeric table.
#warnings("-implicit_impl_as_method")
pub(all) struct RouteSpec {
  destination : IpAddress
  prefix_length : Byte
  gateway : IpAddress?
  output_interface : Int
  table : UInt
  priority : UInt?
  protocol : Byte
  scope : Byte
} derive(Debug, Eq)

///|
#warnings("-implicit_impl_as_method")
pub(all) suberror MutationError {
  InvalidInterfaceIndex(index~ : Int)
  InvalidMtu(mtu~ : UInt)
  InvalidPrefix(prefix_length~ : Byte, maximum~ : Int)
  NonCanonicalDestination
  GatewayFamilyMismatch
  InvalidTable(table~ : UInt)
} derive(Debug, Eq)

///|
fn mutation_flags(mode : AddMode) -> UInt16 {
  // NLM_F_REQUEST | NLM_F_ACK | NLM_F_CREATE | EXCL/REPLACE
  match mode {
    Exclusive => 0x0605
    Replace => 0x0505
  }
}

///|
fn mutation_attribute(
  attribute_type : UInt16,
  payload : Bytes,
) -> @core.NetlinkAttribute {
  { attribute_type, payload, nested: false, network_byte_order: false, }
}

///|
fn u32_payload(value : UInt) -> Bytes {
  let buffer = FixedArray::make(4, b'\x00')
  @core.write_u32_le(buffer, 0, value)
  Bytes::from_array(buffer[:])
}

///|
fn encode_mutation(
  message_type : UInt16,
  sequence : UInt,
  flags : UInt16,
  body : Bytes,
  attributes : ArrayView[@core.NetlinkAttribute],
) -> Bytes raise @core.CodecError {
  let encoded = [
    for attribute in attributes => @core.encode_attribute(attribute)
  ]
  let mut length = body.length()
  for attribute in encoded {
    length = length + attribute.length()
  }
  let payload = FixedArray::make(length, b'\x00')
  for index, byte in body {
    payload[index] = byte
  }
  let mut offset = body.length()
  for attribute in encoded {
    for index, byte in attribute {
      payload[offset + index] = byte
    }
    offset = offset + attribute.length()
  }
  @core.encode_message({
    header: { length: 0, message_type, flags, sequence, port_id: 0, },
    payload: Bytes::from_array(payload[:]),
  })
}

///|
fn ip_family(address : IpAddress) -> Byte {
  match address {
    V4(_) => 2
    V6(_) => 10
  }
}

///|
fn validate_prefix(
  address : IpAddress,
  prefix_length : Byte,
) -> Unit raise MutationError {
  let maximum = match address {
    V4(_) => 32
    V6(_) => 128
  }
  if prefix_length.to_int() > maximum {
    raise InvalidPrefix(prefix_length~, maximum~)
  }
}

///|
/// Encode an acknowledged MTU change, preserving all interface flags.
pub fn encode_set_link_mtu(
  sequence : UInt,
  index : Int,
  mtu : UInt,
) -> Bytes raise {
  if index <= 0 {
    raise MutationError::InvalidInterfaceIndex(index~)
  }
  if mtu == 0 {
    raise MutationError::InvalidMtu(mtu~)
  }
  let body = FixedArray::make(16, b'\x00')
  @core.write_u32_le(body, 4, index.reinterpret_as_uint())
  encode_mutation(rtm_newlink, sequence, 0x0005, Bytes::from_array(body[:]), [
    mutation_attribute(ifla_mtu, u32_payload(mtu)),
  ])
}

///|
fn encode_address_mutation(
  sequence : UInt,
  spec : AddressSpec,
  flags : UInt16,
  deleting : Bool,
) -> Bytes raise {
  if spec.interface_index <= 0 {
    raise MutationError::InvalidInterfaceIndex(index=spec.interface_index)
  }
  validate_prefix(spec.address, spec.prefix_length)
  let body = FixedArray::make(8, b'\x00')
  body[0] = ip_family(spec.address)
  body[1] = spec.prefix_length
  body[3] = spec.scope
  @core.write_u32_le(body, 4, spec.interface_index.reinterpret_as_uint())
  encode_mutation(
    if deleting {
      21
    } else {
      rtm_newaddr
    },
    sequence,
    flags,
    Bytes::from_array(body[:]),
    [
      mutation_attribute(ifa_local, spec.address.to_bytes()),
      mutation_attribute(ifa_address, spec.address.to_bytes()),
    ],
  )
}

///|
/// Add a local address; exclusive creation is the default.
pub fn encode_add_address(
  sequence : UInt,
  spec : AddressSpec,
  mode? : AddMode = Exclusive,
) -> Bytes raise {
  encode_address_mutation(sequence, spec, mutation_flags(mode), false)
}

///|
/// Delete precisely the specified local address and prefix.
pub fn encode_delete_address(
  sequence : UInt,
  spec : AddressSpec,
) -> Bytes raise {
  encode_address_mutation(sequence, spec, 0x0005, true)
}

///|
fn encode_route_mutation(
  sequence : UInt,
  spec : RouteSpec,
  flags : UInt16,
  deleting : Bool,
) -> Bytes raise {
  if spec.output_interface <= 0 {
    raise MutationError::InvalidInterfaceIndex(index=spec.output_interface)
  }
  if spec.table == 0 {
    raise MutationError::InvalidTable(table=spec.table)
  }
  validate_prefix(spec.destination, spec.prefix_length)
  let bytes = spec.destination.to_bytes()
  for index, byte in bytes {
    let remaining = spec.prefix_length.to_int() - index * 8
    let host_mask = if remaining >= 8 {
      0
    } else if remaining <= 0 {
      255
    } else {
      (1 << (8 - remaining)) - 1
    }
    if (byte.to_int() & host_mask) != 0 {
      raise MutationError::NonCanonicalDestination
    }
  }
  if spec.gateway is Some(gateway) &&
    ip_family(gateway) != ip_family(spec.destination) {
    raise MutationError::GatewayFamilyMismatch
  }
  let body = FixedArray::make(12, b'\x00')
  body[0] = ip_family(spec.destination)
  body[1] = spec.prefix_length
  body[4] = if spec.table <= 255 { spec.table.to_byte() } else { 0 }
  body[5] = spec.protocol
  body[6] = spec.scope
  body[7] = 1 // RTN_UNICAST
  let attributes = [
    mutation_attribute(rta_destination, bytes),
    mutation_attribute(
      rta_output_interface,
      u32_payload(spec.output_interface.reinterpret_as_uint()),
    ),
    mutation_attribute(rta_table, u32_payload(spec.table)),
  ]
  if spec.gateway is Some(gateway) {
    attributes.push(mutation_attribute(rta_gateway, gateway.to_bytes()))
  }
  if spec.priority is Some(priority) {
    attributes.push(mutation_attribute(rta_priority, u32_payload(priority)))
  }
  encode_mutation(
    if deleting {
      25
    } else {
      rtm_newroute
    },
    sequence,
    flags,
    Bytes::from_array(body[:]),
    attributes,
  )
}

///|
/// Add a canonical unicast route; exclusive creation is the default.
pub fn encode_add_route(
  sequence : UInt,
  spec : RouteSpec,
  mode? : AddMode = Exclusive,
) -> Bytes raise {
  encode_route_mutation(sequence, spec, mutation_flags(mode), false)
}

///|
/// Delete a route using destination, table, output interface and metric.
pub fn encode_delete_route(sequence : UInt, spec : RouteSpec) -> Bytes raise {
  encode_route_mutation(sequence, spec, 0x0005, true)
}
