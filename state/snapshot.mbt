///|
/// Owned objects; querying belongs to transport/CLI. Collection is not atomic.
pub struct NetworkSnapshot {
  links : Array[@route.Link]
  addresses : Array[@route.Address]
  routes : Array[@route.Route]
  neighbors : Array[@route.Neighbor]
} derive(Debug, Eq)

///|
pub extend NetworkSnapshot with Debug::{to_repr}

///|
pub extend NetworkSnapshot with Eq::{equal, not_equal}

///|
/// Copy collections and unknown-attribute arrays, retaining all domain fields.
pub fn NetworkSnapshot::new(
  links~ : ArrayView[@route.Link],
  addresses~ : ArrayView[@route.Address],
  routes~ : ArrayView[@route.Route],
  neighbors~ : ArrayView[@route.Neighbor],
) -> NetworkSnapshot {
  {
    links: [
      for link in links => {
        { ..link, unknown_attributes: link.unknown_attributes.copy(), }
      }
    ],
    addresses: [
      for address in addresses => {
        { ..address, unknown_attributes: address.unknown_attributes.copy(), }
      }
    ],
    routes: [
      for route in routes => {
        { ..route, unknown_attributes: route.unknown_attributes.copy(), }
      }
    ],
    neighbors: [
      for neighbor in neighbors => {
        { ..neighbor, unknown_attributes: neighbor.unknown_attributes.copy(), }
      }
    ],
  }
}

///|
/// Indices are observation references; names identify desired links.
pub fn NetworkSnapshot::interface_name(
  self : NetworkSnapshot,
  index : Int,
) -> String? {
  for link in self.links {
    if link.index == index {
      return link.name
    }
  }
  None
}

///|
pub fn NetworkSnapshot::link_by_name(
  self : NetworkSnapshot,
  name : String,
) -> @route.Link? {
  for link in self.links {
    if link.name == Some(name) {
      return Some(link)
    }
  }
  None
}
