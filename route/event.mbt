///|
/// Typed multicast changes. Unknown family messages remain inspectable.
#warnings("-implicit_impl_as_method")
pub(all) enum RouteEvent {
  LinkChanged(Link)
  LinkDeleted(Link)
  AddressAdded(Address)
  AddressDeleted(Address)
  RouteAdded(Route)
  RouteDeleted(Route)
  NeighborChanged(Neighbor)
  NeighborDeleted(Neighbor)
  Unknown(@core.NetlinkMessage)
} derive(Debug, Eq)

///|
pub extend RouteEvent with Debug::{to_repr}

///|
pub extend RouteEvent with Eq::{equal, not_equal}

///|
/// Decode a route-family notification; generic controls are handled by transport.
pub fn decode_event(
  message : @core.NetlinkMessage,
) -> RouteEvent raise @core.CodecError {
  match message.header.message_type {
    16 => LinkChanged(decode_link(message))
    17 => LinkDeleted(decode_link(message))
    20 => AddressAdded(decode_address(message))
    21 => AddressDeleted(decode_address(message))
    24 => RouteAdded(decode_route(message))
    25 => RouteDeleted(decode_route(message))
    28 => NeighborChanged(decode_neighbor(message))
    29 => NeighborDeleted(decode_neighbor(message))
    _ => Unknown(message)
  }
}
