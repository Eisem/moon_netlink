///|
fn family_text(family : @route.AddressFamily) -> String {
  match family {
    Ipv4 => "ipv4"
    Ipv6 => "ipv6"
    Other(value) => "other:\{value.to_int()}"
  }
}

///|
fn option_string(value : String?) -> String {
  match value {
    Some(value) => value
    None => "-"
  }
}

///|
fn ip_text(value : @route.IpAddress?) -> String {
  match value {
    Some(value) => value.to_string()
    None => "-"
  }
}

///|
fn mac_text(value : @route.MacAddress?) -> String {
  match value {
    Some(value) => value.to_string()
    None => "-"
  }
}

///|
fn operstate_text(value : @route.LinkOperationalState?) -> String {
  match value {
    None => "-"
    Some(Unknown) => "unknown"
    Some(NotPresent) => "not-present"
    Some(Down) => "down"
    Some(LowerLayerDown) => "lower-layer-down"
    Some(Testing) => "testing"
    Some(Dormant) => "dormant"
    Some(Up) => "up"
    Some(Other(value)) => "other:\{value.to_int()}"
  }
}

///|
fn neighbor_state_text(value : @route.NeighborState) -> String {
  match value {
    None => "none"
    Incomplete => "incomplete"
    Reachable => "reachable"
    Stale => "stale"
    Delay => "delay"
    Probe => "probe"
    Failed => "failed"
    NoArp => "noarp"
    Permanent => "permanent"
    Other(value) => "other:\{value.to_int()}"
  }
}

///|
fn json_string_option(value : String?) -> Json {
  match value {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

///|
fn json_uint_option(value : UInt?) -> Json {
  match value {
    Some(value) => @json.to_json(value)
    None => Json::null()
  }
}

///|
fn json_int_option(value : Int?) -> Json {
  match value {
    Some(value) => @json.to_json(value)
    None => Json::null()
  }
}

///|
fn json_ip(value : @route.IpAddress?) -> Json {
  match value {
    Some(value) => Json::string(value.to_string())
    None => Json::null()
  }
}

///|
fn json_mac(value : @route.MacAddress?) -> Json {
  match value {
    Some(value) => Json::string(value.to_string())
    None => Json::null()
  }
}

///|
fn link_json(link : @route.Link) -> Json {
  {
    "index": @json.to_json(link.index),
    "name": json_string_option(link.name),
    "kind": json_string_option(link.kind),
    "mtu": json_uint_option(link.mtu),
    "mac": json_mac(link.mac),
    "flags": @json.to_json(link.flags),
    "operstate": Json::string(operstate_text(link.operational_state)),
    "master_index": json_int_option(link.master_index),
  }
}

///|
fn address_json(address : @route.Address) -> Json {
  {
    "family": Json::string(family_text(address.family)),
    "interface_index": @json.to_json(address.interface_index),
    "interface_name": json_string_option(address.interface_name),
    "prefix_length": @json.to_json(address.prefix_length),
    "scope": @json.to_json(address.scope),
    "local_address": json_ip(address.local_address),
    "address": json_ip(address.address),
    "label": json_string_option(address.label),
    "flags": @json.to_json(address.flags),
  }
}

///|
fn route_json(route : @route.Route) -> Json {
  {
    "family": Json::string(family_text(route.family)),
    "destination": json_ip(route.destination),
    "destination_prefix_length": @json.to_json(route.destination_prefix_length),
    "source": json_ip(route.source),
    "source_prefix_length": @json.to_json(route.source_prefix_length),
    "gateway": json_ip(route.gateway),
    "preferred_source": json_ip(route.preferred_source),
    "input_interface": json_uint_option(route.input_interface),
    "output_interface": json_uint_option(route.output_interface),
    "table": @json.to_json(route.table),
    "priority": json_uint_option(route.priority),
    "protocol": @json.to_json(route.protocol),
    "scope": @json.to_json(route.scope),
    "route_type": @json.to_json(route.route_type),
    "tos": @json.to_json(route.tos),
    "flags": @json.to_json(route.flags),
  }
}

///|
fn neighbor_json(neighbor : @route.Neighbor) -> Json {
  {
    "family": Json::string(family_text(neighbor.family)),
    "interface_index": @json.to_json(neighbor.interface_index),
    "interface_name": json_string_option(neighbor.interface_name),
    "destination": json_ip(neighbor.destination),
    "link_layer_address": json_mac(neighbor.link_layer_address),
    "state": Json::string(neighbor_state_text(neighbor.state)),
    "flags": @json.to_json(neighbor.flags),
    "neighbor_type": @json.to_json(neighbor.neighbor_type),
    "probes": json_uint_option(neighbor.probes),
  }
}

///|
fn link_line(link : @route.Link) -> String {
  let mtu = match link.mtu {
    Some(value) => value.to_string()
    None => "-"
  }
  "\{link.index}\t\{option_string(link.name)}\tmtu \{mtu}\tmac \{mac_text(link.mac)}\tstate \{operstate_text(link.operational_state)}\tflags 0x\{link.flags.to_string(radix=16)}"
}

///|
fn address_line(address : @route.Address) -> String {
  let raw_value = address_value(address)
  let value = if raw_value == "" { "-" } else { raw_value }
  "\{option_string(address.interface_name)}\t\{family_text(address.family)}\t\{value}/\{address.prefix_length.to_int()}\tscope \{address.scope.to_int()}"
}

///|
fn route_line(route : @route.Route) -> String {
  let destination = match route.destination {
    Some(value) =>
      "\{value.to_string()}/\{route.destination_prefix_length.to_int()}"
    None => "default"
  }
  let output_interface = match route.output_interface {
    Some(value) => value.to_string()
    None => "-"
  }
  "\{family_text(route.family)}\t\{destination}\tvia \{ip_text(route.gateway)}\toif \{output_interface}\ttable \{route.table}"
}

///|
fn neighbor_line(neighbor : @route.Neighbor) -> String {
  "\{option_string(neighbor.interface_name)}\t\{family_text(neighbor.family)}\t\{ip_text(neighbor.destination)}\tlladdr \{mac_text(neighbor.link_layer_address)}\t\{neighbor_state_text(neighbor.state)}"
}

///|
fn format_links(links : Array[@route.Link], json : Bool) -> String {
  sort_links(links)
  if json {
    Json::array([ for link in links => link_json(link) ]).stringify(indent=2)
  } else {
    [ for link in links => link_line(link) ].join("\n")
  }
}

///|
fn format_addresses(addresses : Array[@route.Address], json : Bool) -> String {
  sort_addresses(addresses)
  if json {
    Json::array([ for address in addresses => address_json(address) ]).stringify(
      indent=2,
    )
  } else {
    [ for address in addresses => address_line(address) ].join("\n")
  }
}

///|
fn format_routes(routes : Array[@route.Route], json : Bool) -> String {
  sort_routes(routes)
  if json {
    Json::array([ for route in routes => route_json(route) ]).stringify(
      indent=2,
    )
  } else {
    [ for route in routes => route_line(route) ].join("\n")
  }
}

///|
fn format_neighbors(neighbors : Array[@route.Neighbor], json : Bool) -> String {
  sort_neighbors(neighbors)
  if json {
    Json::array([ for neighbor in neighbors => neighbor_json(neighbor) ]).stringify(
      indent=2,
    )
  } else {
    [ for neighbor in neighbors => neighbor_line(neighbor) ].join("\n")
  }
}
