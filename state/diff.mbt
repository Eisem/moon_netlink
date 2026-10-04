///|
/// Supported mutations with observation values needed for review/compensation.
pub(all) enum Change {
  SetLinkUp(name~ : String, index~ : Int, before~ : Bool, after~ : Bool)
  SetMtu(name~ : String, index~ : Int, before~ : UInt?, after~ : UInt)
  AddAddress(name~ : String, spec~ : @route.AddressSpec)
  DeleteAddress(name~ : String, spec~ : @route.AddressSpec)
  AddRoute(name~ : String, spec~ : @route.RouteSpec)
  DeleteRoute(name~ : String, spec~ : @route.RouteSpec)
} derive(Debug, Eq)

///|
pub extend Change with Debug::{to_repr}

///|
pub extend Change with Eq::{equal, not_equal}

///|
pub struct Diff {
  changes : Array[Change]
} derive(Debug, Eq)

///|
pub extend Diff with Debug::{to_repr}

///|
pub extend Diff with Eq::{equal, not_equal}

///|
fn route_slot_matches(current : @route.Route, desired : DesiredRoute) -> Bool {
  route_destination(current) == Some(desired.destination.to_string()) &&
  current.destination_prefix_length == desired.prefix_length &&
  current.table == desired.table &&
  route_priority(current) == desired_priority(desired)
}

///|
fn same_route_slot(a : DesiredRoute, b : DesiredRoute) -> Bool {
  a.destination == b.destination &&
  a.prefix_length == b.prefix_length &&
  a.table == b.table &&
  desired_priority(a) == desired_priority(b)
}

///|
// Exclusive additions may not silently overwrite a competing kernel object.
fn validate_additions(
  snapshot : NetworkSnapshot,
  desired : DesiredState,
  statuses : ArrayView[IntentStatus],
) -> Unit raise StateError {
  for i, a in desired.routes {
    for j in (i + 1)..<desired.routes.length() {
      let b = desired.routes[j]
      if a.ensure == Present && b.ensure == Present && same_route_slot(a, b) {
        raise ConflictingIntent(identity=route_identity(a))
      }
    }
  }
  for status in statuses {
    if status.satisfied {
      continue
    }
    guard status.interface_index is Some(index) else { continue }
    match status.intent {
      Route(intent) if intent.ensure == Present =>
        for current in snapshot.routes {
          if route_slot_matches(current, intent) &&
            !desired.routes.any(absent => {
              absent.ensure == Absent &&
              current.output_interface is Some(oif) &&
              snapshot.interface_name(oif.reinterpret_as_int()) ==
              Some(absent.interface) &&
              route_matches(current, absent, oif.reinterpret_as_int())
            }) {
            raise ConflictingIntent(identity=route_identity(intent))
          }
        }
      Address(intent) if intent.ensure == Present =>
        for current in snapshot.addresses {
          if current.interface_index == index.reinterpret_as_uint() &&
            local_ip(current) == Some(intent.address) &&
            !desired.addresses.any(absent => {
              absent.ensure == Absent &&
              absent.interface == intent.interface &&
              Some(absent.address) == local_ip(current) &&
              absent.prefix_length == current.prefix_length
            }) {
            raise ConflictingIntent(identity=address_identity(intent))
          }
        }
      _ => ()
    }
  }
}

///|
/// Compute only explicitly requested changes; preflight completes before output.
/// Exact identity removals never imply authoritative deletion of other objects.
pub fn diff(snapshot : NetworkSnapshot, desired : DesiredState) -> Diff raise {
  let statuses = evaluate_intent(snapshot, desired)
  validate_additions(snapshot, desired, statuses)
  let changes : Array[Change] = []
  for status in statuses {
    if status.satisfied {
      continue
    }
    guard status.interface_index is Some(index) else { continue }
    match status.intent {
      Link(intent) => {
        let link = snapshot.link_by_name(intent.name).unwrap()
        if intent.up is Some(up) && up != ((link.flags & 1) != 0) {
          changes.push(
            SetLinkUp(
              name=intent.name,
              index~,
              before=(link.flags & 1) != 0,
              after=up,
            ),
          )
        }
        if intent.mtu is Some(mtu) && Some(mtu) != link.mtu {
          changes.push(
            SetMtu(name=intent.name, index~, before=link.mtu, after=mtu),
          )
        }
      }
      Address(intent) => {
        let spec : @route.AddressSpec = {
          interface_index: index,
          address: intent.address,
          prefix_length: intent.prefix_length,
          scope: intent.scope,
        }
        changes.push(
          if intent.ensure == Present {
            AddAddress(name=intent.interface, spec~)
          } else {
            DeleteAddress(name=intent.interface, spec~)
          },
        )
      }
      Route(intent) => {
        let spec : @route.RouteSpec = {
          destination: intent.destination,
          prefix_length: intent.prefix_length,
          gateway: intent.gateway,
          output_interface: index,
          table: intent.table,
          priority: Some(desired_priority(intent)),
          protocol: intent.protocol,
          scope: intent.scope,
        }
        changes.push(
          if intent.ensure == Present {
            AddRoute(name=intent.interface, spec~)
          } else {
            DeleteRoute(name=intent.interface, spec~)
          },
        )
      }
    }
  }
  changes.sort_by((a, b) => "\{Repr(a)}".compare("\{Repr(b)}"))
  { changes, }
}
