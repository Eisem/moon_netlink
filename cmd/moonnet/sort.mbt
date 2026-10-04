///|
fn compare_int(left : Int, right : Int) -> Int {
  if left < right {
    -1
  } else if left > right {
    1
  } else {
    0
  }
}

///|
fn compare_uint(left : UInt, right : UInt) -> Int {
  if left < right {
    -1
  } else if left > right {
    1
  } else {
    0
  }
}

///|
fn compare_byte(left : Byte, right : Byte) -> Int {
  compare_int(left.to_int(), right.to_int())
}

///|
fn compare_optional_uint(left : UInt?, right : UInt?) -> Int {
  match (left, right) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(left), Some(right)) => compare_uint(left, right)
  }
}

///|
fn family_key(family : @route.AddressFamily) -> Int {
  match family {
    Ipv4 => 4
    Ipv6 => 6
    Other(value) => 100 + value.to_int()
  }
}

///|
fn address_value(address : @route.Address) -> String {
  match address.local_address {
    Some(value) => value.to_string()
    None =>
      match address.address {
        Some(value) => value.to_string()
        None => ""
      }
  }
}

///|
fn route_ip_key(value : @route.IpAddress?) -> String {
  match value {
    Some(value) => value.to_string()
    None => ""
  }
}

///|
fn sort_links(links : Array[@route.Link]) -> Unit {
  links.sort_by((left, right) => {
    let by_index = compare_int(left.index, right.index)
    if by_index != 0 {
      by_index
    } else {
      compare_string_option(left.name, right.name)
    }
  })
}

///|
fn compare_string_option(left : String?, right : String?) -> Int {
  match (left, right) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(left), Some(right)) => left.compare(right)
  }
}

///|
fn sort_addresses(addresses : Array[@route.Address]) -> Unit {
  addresses.sort_by((left, right) => {
    let by_index = compare_uint(left.interface_index, right.interface_index)
    if by_index != 0 {
      return by_index
    }
    let by_family = compare_int(
      family_key(left.family),
      family_key(right.family),
    )
    if by_family != 0 {
      return by_family
    }
    let by_value = address_value(left).compare(address_value(right))
    if by_value != 0 {
      return by_value
    }
    let by_prefix = compare_byte(left.prefix_length, right.prefix_length)
    if by_prefix != 0 {
      return by_prefix
    }
    let by_scope = compare_byte(left.scope, right.scope)
    if by_scope != 0 {
      return by_scope
    }
    let by_label = compare_string_option(left.label, right.label)
    if by_label != 0 {
      return by_label
    }
    compare_uint(left.flags, right.flags)
  })
}

///|
fn sort_routes(routes : Array[@route.Route]) -> Unit {
  routes.sort_by((left, right) => {
    let by_family = compare_int(
      family_key(left.family),
      family_key(right.family),
    )
    if by_family != 0 {
      return by_family
    }
    let by_table = compare_uint(left.table, right.table)
    if by_table != 0 {
      return by_table
    }
    let by_destination = route_ip_key(left.destination).compare(
      route_ip_key(right.destination),
    )
    if by_destination != 0 {
      return by_destination
    }
    let by_prefix = compare_byte(
      left.destination_prefix_length,
      right.destination_prefix_length,
    )
    if by_prefix != 0 {
      return by_prefix
    }
    let by_output = compare_optional_uint(
      left.output_interface,
      right.output_interface,
    )
    if by_output != 0 {
      return by_output
    }
    let by_gateway = route_ip_key(left.gateway).compare(
      route_ip_key(right.gateway),
    )
    if by_gateway != 0 {
      return by_gateway
    }
    let by_priority = compare_optional_uint(left.priority, right.priority)
    if by_priority != 0 {
      return by_priority
    }
    let by_source = route_ip_key(left.source).compare(
      route_ip_key(right.source),
    )
    if by_source != 0 {
      return by_source
    }
    let by_source_prefix = compare_byte(
      left.source_prefix_length,
      right.source_prefix_length,
    )
    if by_source_prefix != 0 {
      return by_source_prefix
    }
    let by_preferred_source = route_ip_key(left.preferred_source).compare(
      route_ip_key(right.preferred_source),
    )
    if by_preferred_source != 0 {
      return by_preferred_source
    }
    let by_input = compare_optional_uint(
      left.input_interface,
      right.input_interface,
    )
    if by_input != 0 {
      return by_input
    }
    let by_protocol = compare_byte(left.protocol, right.protocol)
    if by_protocol != 0 {
      return by_protocol
    }
    let by_scope = compare_byte(left.scope, right.scope)
    if by_scope != 0 {
      return by_scope
    }
    let by_type = compare_byte(left.route_type, right.route_type)
    if by_type != 0 {
      return by_type
    }
    let by_tos = compare_byte(left.tos, right.tos)
    if by_tos != 0 {
      return by_tos
    }
    compare_uint(left.flags, right.flags)
  })
}

///|
fn sort_neighbors(neighbors : Array[@route.Neighbor]) -> Unit {
  neighbors.sort_by((left, right) => {
    let by_index = compare_int(left.interface_index, right.interface_index)
    if by_index != 0 {
      return by_index
    }
    let by_family = compare_int(
      family_key(left.family),
      family_key(right.family),
    )
    if by_family != 0 {
      return by_family
    }
    let by_destination = route_ip_key(left.destination).compare(
      route_ip_key(right.destination),
    )
    if by_destination != 0 {
      return by_destination
    }
    let left_mac = match left.link_layer_address {
      Some(value) => value.to_string()
      None => ""
    }
    let right_mac = match right.link_layer_address {
      Some(value) => value.to_string()
      None => ""
    }
    let by_mac = left_mac.compare(right_mac)
    if by_mac != 0 {
      return by_mac
    }
    let by_state = neighbor_state_text(left.state).compare(
      neighbor_state_text(right.state),
    )
    if by_state != 0 {
      return by_state
    }
    let by_flags = compare_byte(left.flags, right.flags)
    if by_flags != 0 {
      return by_flags
    }
    let by_type = compare_byte(left.neighbor_type, right.neighbor_type)
    if by_type != 0 {
      return by_type
    }
    compare_optional_uint(left.probes, right.probes)
  })
}
