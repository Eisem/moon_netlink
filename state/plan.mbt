///|
pub(all) struct PlanStep {
  change : Change
  reason : String
  dangerous : Bool
} derive(Debug, Eq)

///|
pub extend PlanStep with Debug::{to_repr}

///|
pub extend PlanStep with Eq::{equal, not_equal}

///|
/// A reviewable ordered plan. Producing a plan never executes a mutation.
pub struct Plan {
  steps : Array[PlanStep]
} derive(Debug, Eq)

///|
pub extend Plan with Debug::{to_repr}

///|
pub extend Plan with Eq::{equal, not_equal}

///|
fn change_rank(change : Change) -> Int {
  match change {
    DeleteRoute(..) => 0
    DeleteAddress(..) => 1
    SetMtu(..) => 2
    SetLinkUp(after=true, ..) => 3
    AddAddress(..) => 4
    AddRoute(..) => 5
    SetLinkUp(after=false, ..) => 6
  }
}

///|
pub fn Change::interface_name(self : Change) -> String {
  match self {
    SetLinkUp(name~, ..)
    | SetMtu(name~, ..)
    | AddAddress(name~, ..)
    | DeleteAddress(name~, ..)
    | AddRoute(name~, ..)
    | DeleteRoute(name~, ..) => name
  }
}

///|
fn change_reason(change : Change) -> String {
  match change {
    SetLinkUp(..) => "administrative state differs from explicit intent"
    SetMtu(..) => "MTU differs from explicit intent"
    AddAddress(..) => "explicit present address is missing"
    DeleteAddress(..) => "explicit absent address exists"
    AddRoute(..) => "explicit present route is missing"
    DeleteRoute(..) => "explicit absent route exists"
  }
}

///|
/// Deletions precede preparation/additions; routes follow addresses, DOWN last.
/// Complete raw change values break ties independently of desired input order.
pub fn build_plan(
  snapshot : NetworkSnapshot,
  desired : DesiredState,
) -> Plan raise {
  let changes = diff(snapshot, desired).changes
  changes.sort_by((a, b) => {
    let rank_a = change_rank(a)
    let rank_b = change_rank(b)
    if rank_a < rank_b {
      -1
    } else if rank_a > rank_b {
      1
    } else {
      "\{Repr(a)}".compare("\{Repr(b)}")
    }
  })
  {
    steps: [
      for change in changes => {
        let loopback = change.interface_name() == "lo" ||
          (match snapshot.link_by_name(change.interface_name()) {
            Some(link) => (link.flags & 8) != 0
            None => false
          })
        let default_route = match change {
          AddRoute(spec~, ..) | DeleteRoute(spec~, ..) =>
            spec.prefix_length == 0
          _ => false
        }
        {
          change,
          reason: change_reason(change),
          dangerous: loopback || default_route,
        }
      }
    ],
  }
}

///|
pub fn Change::to_json(self : Change) -> Json {
  match self {
    SetLinkUp(name~, index~, before~, after~) =>
      {
        "operation": Json::string(
          if after {
            "set_link_up"
          } else {
            "set_link_down"
          },
        ),
        "interface": Json::string(name),
        "interface_index": @json.to_json(index),
        "before": Json::boolean(before),
        "after": Json::boolean(after),
      }
    SetMtu(name~, index~, before~, after~) =>
      {
        "operation": "set_mtu",
        "interface": Json::string(name),
        "interface_index": @json.to_json(index),
        "before": uint_json(before),
        "after": @json.to_json(after),
      }
    AddAddress(name~, spec~) | DeleteAddress(name~, spec~) =>
      {
        "operation": Json::string(
          match self {
            AddAddress(..) => "add_address"
            _ => "delete_address"
          },
        ),
        "interface": Json::string(name),
        "interface_index": @json.to_json(spec.interface_index),
        "address": Json::string(spec.address.to_string()),
        "prefix_length": @json.to_json(spec.prefix_length),
        "scope": @json.to_json(spec.scope),
      }
    AddRoute(name~, spec~) | DeleteRoute(name~, spec~) =>
      {
        "operation": Json::string(
          match self {
            AddRoute(..) => "add_route"
            _ => "delete_route"
          },
        ),
        "interface": Json::string(name),
        "interface_index": @json.to_json(spec.output_interface),
        "destination": Json::string(spec.destination.to_string()),
        "prefix_length": @json.to_json(spec.prefix_length),
        "gateway": ip_json(spec.gateway),
        "table": @json.to_json(spec.table),
        "priority": uint_json(spec.priority),
        "protocol": @json.to_json(spec.protocol),
        "scope": @json.to_json(spec.scope),
      }
  }
}

///|
pub fn Plan::to_json(self : Plan) -> Json {
  {
    "schema_version": 1,
    "steps": Json::array(
      [
        for step in self.steps => {
          {
            "change": step.change.to_json(),
            "reason": Json::string(step.reason),
            "dangerous": Json::boolean(step.dangerous),
          }
        }
      ],
    ),
  }
}
