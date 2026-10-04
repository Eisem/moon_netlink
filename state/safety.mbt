///|
pub(all) suberror SafetyError {
  ProtectedResource(step~ : Int, interface~ : String, reason~ : String)
  StaleInterface(
    interface~ : String,
    planned_index~ : Int,
    observed_index~ : Int?
  )
} derive(Debug, Eq)

///|
pub extend SafetyError with Debug::{to_repr}

///|
pub extend SafetyError with Eq::{equal, not_equal}

///|
pub fn Change::interface_index(self : Change) -> Int {
  match self {
    SetLinkUp(index~, ..) | SetMtu(index~, ..) => index
    AddAddress(spec~, ..) | DeleteAddress(spec~, ..) => spec.interface_index
    AddRoute(spec~, ..) | DeleteRoute(spec~, ..) => spec.output_interface
  }
}

///|
/// Validate every operation before any write. Recompute protection from actual
/// change values and observed link flags, rather than trusting display markers.
/// Dangerous permits protected resources but never stale/missing interfaces.
/// A snapshot is an observation; this cannot prevent concurrent kernel changes.
pub fn validate_plan(
  plan : Plan,
  snapshot : NetworkSnapshot,
  dangerous? : Bool = false,
) -> Unit raise {
  for position, step in plan.steps {
    let name = step.change.interface_name()
    let index = step.change.interface_index()
    let observed = snapshot.link_by_name(name)
    let observed_index = observed.map(link => link.index)
    if index <= 0 || observed_index != Some(index) {
      raise SafetyError::StaleInterface(
        interface=name,
        planned_index=index,
        observed_index~,
      )
    }
    let loopback = name == "lo" ||
      observed.map(link => (link.flags & 8) != 0).unwrap_or(false)
    let default_route = match step.change {
      AddRoute(spec~, ..) | DeleteRoute(spec~, ..) => spec.prefix_length == 0
      _ => false
    }
    if !dangerous && (loopback || default_route) {
      raise SafetyError::ProtectedResource(
        step=position,
        interface=name,
        reason=if loopback { "loopback" } else { "default route" },
      )
    }
    // Public step arrays can be edited by callers; validate complete SDK specs.
    match step.change {
      SetLinkUp(index~, after~, ..) =>
        ignore(@route.encode_set_link_state(1, index, after))
      SetMtu(index~, after~, ..) =>
        ignore(@route.encode_set_link_mtu(1, index, after))
      AddAddress(spec~, ..) => ignore(@route.encode_add_address(1, spec))
      DeleteAddress(spec~, ..) => ignore(@route.encode_delete_address(1, spec))
      AddRoute(spec~, ..) => ignore(@route.encode_add_route(1, spec))
      DeleteRoute(spec~, ..) => ignore(@route.encode_delete_route(1, spec))
    }
  }
}
