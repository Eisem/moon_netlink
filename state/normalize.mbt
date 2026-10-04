///|
/// A new snapshot sorted by explicit identity then every retained raw field.
/// Address/Neighbor names are resolved against this observation's links.
pub fn normalize(snapshot : NetworkSnapshot) -> NetworkSnapshot {
  let result = NetworkSnapshot::new(
    links=snapshot.links,
    addresses=snapshot.addresses,
    routes=snapshot.routes,
    neighbors=snapshot.neighbors,
  )
  result.links.sort_by((a, b) => {
    (a.name.unwrap_or("") + "\{Repr(a)}").compare(
      b.name.unwrap_or("") + "\{Repr(b)}",
    )
  })
  for index, address in result.addresses {
    result.addresses[index] = {
      ..address,
      interface_name: result.interface_name(
        address.interface_index.reinterpret_as_int(),
      ),
    }
  }
  result.addresses.sort_by((a, b) => {
    (a.interface_name.unwrap_or("") + "\{Repr(a)}").compare(
      b.interface_name.unwrap_or("") + "\{Repr(b)}",
    )
  })
  result.routes.sort_by((a, b) => "\{Repr(a)}".compare("\{Repr(b)}"))
  for index, neighbor in result.neighbors {
    result.neighbors[index] = {
      ..neighbor,
      interface_name: result.interface_name(neighbor.interface_index),
    }
  }
  result.neighbors.sort_by((a, b) => {
    (a.interface_name.unwrap_or("") + "\{Repr(a)}").compare(
      b.interface_name.unwrap_or("") + "\{Repr(b)}",
    )
  })
  result
}

///|
fn ip_json(value : @route.IpAddress?) -> Json {
  match value {
    Some(ip) => Json::string(ip.to_string())
    None => Json::null()
  }
}

///|
fn string_json(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn uint_json(value : UInt?) -> Json {
  match value {
    Some(number) => @json.to_json(number)
    None => Json::null()
  }
}

///|
/// Canonical default destination text; a missing nonzero prefix stays missing.
pub fn route_destination(route : @route.Route) -> String? {
  if route.destination is Some(ip) {
    return Some(ip.to_string())
  }
  if route.destination_prefix_length != 0 {
    return None
  }
  match route.family {
    Ipv4 => Some("0.0.0.0")
    Ipv6 => Some("::")
    Other(_) => None
  }
}

///|
/// Absent metric is zero for IPv4, 1024 for IPv6 in the supported unicast subset.
pub fn route_priority(route : @route.Route) -> UInt {
  route.priority.unwrap_or(
    match route.family {
      Ipv6 => 1024
      _ => 0
    },
  )
}

///|
/// Versioned normalized projection plus raw Debug diagnostics for every object.
/// Indices and volatile flags are observation data, not desired identities.
pub fn NetworkSnapshot::to_json(self : NetworkSnapshot) -> Json {
  let snapshot = normalize(self)
  {
    "schema_version": 1,
    "links": Json::array(
      [
        for link in snapshot.links => {
          {
            "name": string_json(link.name),
            "index": @json.to_json(link.index),
            "up": Json::boolean((link.flags & 1) != 0),
            "mtu": uint_json(link.mtu),
            "raw": Json::string("\{Repr(link)}"),
          }
        }
      ],
    ),
    "addresses": Json::array(
      [
        for address in snapshot.addresses => {
          {
            "interface": string_json(address.interface_name),
            "address": ip_json(
              match address.local_address {
                Some(_) => address.local_address
                None => address.address
              },
            ),
            "peer": ip_json(address.address),
            "prefix_length": @json.to_json(address.prefix_length),
            "scope": @json.to_json(address.scope),
            "raw": Json::string("\{Repr(address)}"),
          }
        }
      ],
    ),
    "routes": Json::array(
      [
        for route in snapshot.routes => {
          {
            "interface": string_json(
              match route.output_interface {
                Some(index) =>
                  snapshot.interface_name(index.reinterpret_as_int())
                None => None
              },
            ),
            "destination": string_json(route_destination(route)),
            "prefix_length": @json.to_json(route.destination_prefix_length),
            "gateway": ip_json(route.gateway),
            "table": @json.to_json(route.table),
            "priority": @json.to_json(route_priority(route)),
            "protocol": @json.to_json(route.protocol),
            "scope": @json.to_json(route.scope),
            "raw": Json::string("\{Repr(route)}"),
          }
        }
      ],
    ),
    "neighbors": Json::array(
      [
        for neighbor in snapshot.neighbors => {
          {
            "interface": string_json(neighbor.interface_name),
            "destination": ip_json(neighbor.destination),
            "state": Json::string("\{Repr(neighbor.state)}"),
            "raw": Json::string("\{Repr(neighbor)}"),
          }
        }
      ],
    ),
  }
}
