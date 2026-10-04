///|
pub(all) enum ResourceIntent {
  Link(DesiredLink)
  Address(DesiredAddress)
  Route(DesiredRoute)
} derive(Debug, Eq)

///|
pub extend ResourceIntent with Debug::{to_repr}

///|
pub extend ResourceIntent with Eq::{equal, not_equal}

///|
/// Observation of exactly one explicitly managed resource.
pub(all) struct IntentStatus {
  intent : ResourceIntent
  interface_index : Int?
  exists : Bool
  satisfied : Bool
} derive(Debug, Eq)

///|
pub extend IntentStatus with Debug::{to_repr}

///|
pub extend IntentStatus with Eq::{equal, not_equal}

///|
fn resolve_interface(
  snapshot : NetworkSnapshot,
  name : String,
  ensure : Ensure,
) -> Int? raise StateError {
  match snapshot.link_by_name(name) {
    Some(link) => Some(link.index)
    None if ensure == Absent => None
    None => raise MissingInterface(name~)
  }
}

///|
fn local_ip(address : @route.Address) -> @route.IpAddress? {
  match address.local_address {
    Some(_) => address.local_address
    None => address.address
  }
}

///|
fn route_matches(
  current : @route.Route,
  desired : DesiredRoute,
  index : Int,
) -> Bool {
  route_destination(current) == Some(desired.destination.to_string()) &&
  current.destination_prefix_length == desired.prefix_length &&
  current.gateway == desired.gateway &&
  current.output_interface == Some(index.reinterpret_as_uint()) &&
  current.table == desired.table &&
  route_priority(current) == desired_priority(desired)
}

///|
/// Evaluate only explicit intent. Missing interfaces satisfy absent Address/
/// Route intents, but present intents fail preflight. Links must already exist;
/// absent Link is unsupported because the SDK cannot delete links yet.
pub fn evaluate_intent(
  snapshot : NetworkSnapshot,
  desired : DesiredState,
) -> Array[IntentStatus] raise {
  validate_desired(desired)
  let result : Array[IntentStatus] = []
  for intent in desired.links {
    if intent.ensure == Absent {
      raise StateError::UnsupportedIntent(
        reason="absent Link requires unsupported link deletion; use up=false to disable",
      )
    }
    guard snapshot.link_by_name(intent.name) is Some(link) else {
      raise StateError::MissingInterface(name=intent.name)
    }
    let satisfied = (
        intent.up is None || intent.up == Some((link.flags & 1) != 0)
      ) &&
      (intent.mtu is None || intent.mtu == link.mtu)
    result.push({
      intent: Link(intent),
      interface_index: Some(link.index),
      exists: true,
      satisfied,
    })
  }
  for intent in desired.addresses {
    let index = resolve_interface(snapshot, intent.interface, intent.ensure)
    let mut exists = false
    if index is Some(index) {
      for address in snapshot.addresses {
        if address.interface_index == index.reinterpret_as_uint() &&
          local_ip(address) == Some(intent.address) &&
          address.prefix_length == intent.prefix_length {
          if address.scope != intent.scope ||
            (
              address.local_address is Some(local_address) &&
              address.address is Some(peer) &&
              local_address != peer
            ) {
            raise StateError::UnsupportedCurrentResource(
              identity=address_identity(intent),
            )
          }
          exists = true
        }
      }
    }
    result.push({
      intent: Address(intent),
      interface_index: index,
      exists,
      satisfied: exists == (intent.ensure == Present),
    })
  }
  for intent in desired.routes {
    let index = resolve_interface(snapshot, intent.interface, intent.ensure)
    let mut exists = false
    if index is Some(index) {
      for route in snapshot.routes {
        if route_matches(route, intent, index) {
          if route.route_type != 1 ||
            route.protocol != intent.protocol ||
            route.scope != intent.scope ||
            route.source_prefix_length != 0 ||
            route.source is Some(_) ||
            route.input_interface is Some(_) ||
            route.tos != 0 ||
            route.unknown_attributes.any(attribute => {
              [9, 18, 19, 21, 22, 30].contains(
                attribute.attribute_type.to_int(),
              )
            }) {
            raise StateError::UnsupportedCurrentResource(
              identity=route_identity(intent),
            )
          }
          exists = true
        }
      }
    }
    result.push({
      intent: Route(intent),
      interface_index: index,
      exists,
      satisfied: exists == (intent.ensure == Present),
    })
  }
  result
}
