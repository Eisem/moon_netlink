///|
test "parse the four show commands and reject extra arguments" {
  for kind in ["link", "address", "route", "neighbor"] {
    guard parse_cli_args(["moonnet", kind, "show"]) is Some(options) else {
      fail("expected \{kind} show to parse")
    }
    assert_false(options.json)
    guard parse_cli_args(["moonnet", kind, "show", "--json"]) is Some(json) else {
      fail("expected \{kind} show --json to parse")
    }
    assert_true(json.json)
  }
  assert_true(parse_cli_args(["moonnet", "link"]) is None)
  assert_true(parse_cli_args(["moonnet", "link", "delete"]) is None)
  assert_true(parse_cli_args(["moonnet", "link", "show", "--yaml"]) is None)
}

///|
test "link JSON is stably sorted by interface index" {
  let links : Array[@route.Link] = [
    {
      index: 9,
      name: Some("zeta"),
      kind: None,
      mtu: Some(1500),
      mac: None,
      flags: 1,
      operational_state: Some(Up),
      master_index: None,
      unknown_attributes: [],
    },
    {
      index: 1,
      name: Some("lo"),
      kind: None,
      mtu: Some(65536),
      mac: None,
      flags: 8,
      operational_state: Some(Unknown),
      master_index: None,
      unknown_attributes: [],
    },
  ]
  let output = format_links(links, true)
  ignore(@json.parse(output))
  assert_true(output.contains("\"mtu\": 65536"))
  guard output.find("\"index\": 1") is Some(first) &&
    output.find("\"index\": 9") is Some(second) else {
    fail("expected both indices in JSON output")
  }
  assert_true(first < second)
}

///|
test "address route and neighbor sort keys are deterministic" {
  let addresses : Array[@route.Address] = [
    {
      family: Ipv6,
      interface_index: 2,
      interface_name: Some("eth0"),
      prefix_length: 64,
      scope: 0,
      local_address: None,
      address: Some(@route.IpAddress::parse("2001:db8::1")),
      label: None,
      flags: 0,
      unknown_attributes: [],
    },
    {
      family: Ipv4,
      interface_index: 1,
      interface_name: Some("lo"),
      prefix_length: 8,
      scope: 0,
      local_address: Some(@route.IpAddress::parse("127.0.0.1")),
      address: None,
      label: None,
      flags: 0,
      unknown_attributes: [],
    },
  ]
  sort_addresses(addresses)
  assert_eq(addresses[0].interface_index, 1)
  let routes : Array[@route.Route] = [
    {
      family: Ipv6,
      destination: None,
      destination_prefix_length: 0,
      source: None,
      source_prefix_length: 0,
      gateway: None,
      preferred_source: None,
      input_interface: None,
      output_interface: Some(2),
      table: 254,
      priority: None,
      protocol: 3,
      scope: 0,
      route_type: 1,
      tos: 0,
      flags: 0,
      unknown_attributes: [],
    },
    {
      family: Ipv4,
      destination: None,
      destination_prefix_length: 0,
      source: None,
      source_prefix_length: 0,
      gateway: None,
      preferred_source: None,
      input_interface: None,
      output_interface: Some(1),
      table: 254,
      priority: None,
      protocol: 3,
      scope: 0,
      route_type: 1,
      tos: 0,
      flags: 0,
      unknown_attributes: [],
    },
  ]
  sort_routes(routes)
  assert_eq(routes[0].family, Ipv4)
  let neighbors : Array[@route.Neighbor] = [
    {
      family: Ipv4,
      interface_index: 8,
      interface_name: None,
      destination: Some(@route.IpAddress::parse("192.0.2.8")),
      link_layer_address: None,
      state: Reachable,
      flags: 0,
      neighbor_type: 1,
      probes: None,
      unknown_attributes: [],
    },
    {
      family: Ipv4,
      interface_index: 2,
      interface_name: None,
      destination: Some(@route.IpAddress::parse("192.0.2.2")),
      link_layer_address: None,
      state: Reachable,
      flags: 0,
      neighbor_type: 1,
      probes: None,
      unknown_attributes: [],
    },
  ]
  sort_neighbors(neighbors)
  assert_eq(neighbors[0].interface_index, 2)
}
