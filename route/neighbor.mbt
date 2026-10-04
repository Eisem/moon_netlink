///|
pub let rtm_newneigh : UInt16 = 28

///|
pub let rtm_getneigh : UInt16 = 30

///|
let nda_destination : UInt16 = 1

///|
let nda_link_layer_address : UInt16 = 2

///|
let nda_probes : UInt16 = 4

///|
/// Linux neighbour-unreachability-detection state from `ndmsg.ndm_state`.
#warnings("-implicit_impl_as_method")
pub(all) enum NeighborState {
  None
  Incomplete
  Reachable
  Stale
  Delay
  Probe
  Failed
  NoArp
  Permanent
  Other(UInt16)
} derive(Debug, Eq)

///|
pub extend NeighborState with Debug::{to_repr}

///|
pub extend NeighborState with Eq::{equal, not_equal}

///|
/// One decoded `RTM_NEWNEIGH` object. Interface names are resolved later by
/// joining `interface_index` with Link data in `RouteClient`.
#warnings("-implicit_impl_as_method")
pub(all) struct Neighbor {
  family : AddressFamily
  interface_index : Int
  interface_name : String?
  destination : IpAddress?
  link_layer_address : MacAddress?
  state : NeighborState
  flags : Byte
  neighbor_type : Byte
  probes : UInt?
  unknown_attributes : Array[@core.NetlinkAttribute]
} derive(Debug, Eq)

///|
pub extend Neighbor with Debug::{to_repr}

///|
pub extend Neighbor with Eq::{equal, not_equal}

///|
/// Build an all-family `RTM_GETNEIGH` dump request.
pub fn encode_get_neighbors(sequence : UInt) -> Bytes {
  let message_length = 28
  let buffer = FixedArray::make(message_length, b'\x00')
  @core.write_u32_le(buffer, 0, message_length.reinterpret_as_uint())
  @core.write_u16_le(buffer, 4, rtm_getneigh)
  @core.write_u16_le(buffer, 6, 0x0301)
  @core.write_u32_le(buffer, 8, sequence)
  @core.write_u32_le(buffer, 12, 0)
  Bytes::from_array(buffer[:])
}

///|
fn decode_neighbor_state(value : UInt16) -> NeighborState {
  match value {
    0x00 => None
    0x01 => Incomplete
    0x02 => Reachable
    0x04 => Stale
    0x08 => Delay
    0x10 => Probe
    0x20 => Failed
    0x40 => NoArp
    0x80 => Permanent
    other => Other(other)
  }
}

///|
/// Decode one `RTM_NEWNEIGH` body and preserve attributes not yet modeled.
pub fn decode_neighbor(
  message : @core.NetlinkMessage,
) -> Neighbor raise @core.CodecError {
  let payload = message.payload[:]
  if payload.length() < 12 {
    raise Truncated(
      context="ndmsg",
      offset=0,
      needed=12,
      available=payload.length(),
    )
  }
  let family = decode_address_family(payload[0])
  let attributes = @core.decode_attributes(payload, 12)
  let mut destination : IpAddress? = None
  let mut link_layer_address : MacAddress? = None
  let mut probes : UInt? = None
  let unknown : Array[@core.NetlinkAttribute] = []
  for attribute in attributes {
    if attribute.attribute_type == nda_destination {
      destination = decode_ip_address(family, attribute, "NDA_DST")
      if family is Other(_) {
        unknown.push(attribute)
      }
    } else if attribute.attribute_type == nda_link_layer_address {
      require_attribute_length(attribute, 6, "NDA_LLADDR")
      link_layer_address = Some({ bytes: attribute.payload, })
    } else if attribute.attribute_type == nda_probes {
      require_attribute_length(attribute, 4, "NDA_PROBES")
      probes = Some(@core.read_u32_le(attribute.payload, 0))
    } else {
      unknown.push(attribute)
    }
  }
  {
    family,
    interface_index: @core.read_i32_le(payload, 4),
    interface_name: None,
    destination,
    link_layer_address,
    state: decode_neighbor_state(@core.read_u16_le(payload, 8)),
    flags: payload[10],
    neighbor_type: payload[11],
    probes,
    unknown_attributes: unknown,
  }
}

///|
/// Decode only `RTM_NEWNEIGH` messages from a completed dump.
pub fn decode_neighbors(
  messages : ArrayView[@core.NetlinkMessage],
) -> Array[Neighbor] raise @core.CodecError {
  let neighbors : Array[Neighbor] = []
  for message in messages {
    if message.header.message_type == rtm_newneigh {
      neighbors.push(decode_neighbor(message))
    }
  }
  neighbors
}
