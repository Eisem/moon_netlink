///|
fn test_link(index : Int, name : String) -> @route.Link {
  {
    index,
    name: Some(name),
    kind: None,
    mtu: Some(1500),
    mac: None,
    flags: 1,
    operational_state: None,
    master_index: None,
    unknown_attributes: [],
  }
}

///|
fn test_address(index : UInt, ip : String) -> @route.Address raise {
  {
    family: Ipv6,
    interface_index: index,
    interface_name: None,
    prefix_length: 64,
    scope: 0,
    local_address: None,
    address: Some(@route.IpAddress::parse(ip)),
    label: None,
    flags: 64,
    unknown_attributes: [],
  }
}

///|
fn test_route(index : UInt) -> @route.Route {
  {
    family: Ipv6,
    destination: None,
    destination_prefix_length: 0,
    source: None,
    source_prefix_length: 0,
    gateway: None,
    preferred_source: None,
    input_interface: None,
    output_interface: Some(index),
    table: 254,
    priority: Some(1024),
    protocol: 4,
    scope: 0,
    route_type: 1,
    tos: 0,
    flags: 0,
    unknown_attributes: [],
  }
}

///|
test "explicit intent preserves unmanaged resources and resolves IPv6 local/default identities" {
  let snapshot = @state.NetworkSnapshot::new(
    links=[test_link(7, "veth0"), test_link(8, "unmanaged")],
    addresses=[test_address(7, "2001:db8::1"), test_address(8, "2001:db8::2")],
    routes=[test_route(7)],
    neighbors=[],
  )
  let address : @state.DesiredAddress = {
    interface: "veth0",
    ensure: Present,
    address: @route.IpAddress::parse("2001:db8::1"),
    prefix_length: 64,
    scope: 0,
  }
  let route : @state.DesiredRoute = {
    interface: "veth0",
    ensure: Present,
    destination: @route.IpAddress::parse("::"),
    prefix_length: 0,
    gateway: None,
    table: 254,
    priority: 0,
    protocol: 4,
    scope: 0,
  }
  let statuses = @state.evaluate_intent(snapshot, {
    links: [],
    addresses: [address],
    routes: [route],
  })
  assert_eq(statuses.length(), 2)
  assert_true(statuses.all(status => status.satisfied))
  assert_eq(statuses[0].interface_index, Some(7))
  let absent = @state.evaluate_intent(snapshot, {
    links: [],
    addresses: [{ ..address, ensure: Absent, }],
    routes: [],
  })
  assert_false(absent[0].satisfied)
  assert_true(absent[0].exists)
  assert_eq(snapshot.addresses.length(), 2)
}

///|
test "missing interfaces satisfy absence and reject presence before mutation" {
  let snapshot = @state.NetworkSnapshot::new(
    links=[],
    addresses=[],
    routes=[],
    neighbors=[],
  )
  let address : @state.DesiredAddress = {
    interface: "missing",
    ensure: Absent,
    address: @route.IpAddress::parse("192.0.2.1"),
    prefix_length: 24,
    scope: 0,
  }
  assert_true(
    @state.evaluate_intent(snapshot, {
      links: [],
      addresses: [address],
      routes: [],
    })[0].satisfied,
  )
  try
    @state.evaluate_intent(snapshot, {
      links: [],
      addresses: [{ ..address, ensure: Present, }],
      routes: [],
    })
  catch {
    @state.StateError::MissingInterface(name~) => assert_eq(name, "missing")
    err => fail("unexpected preflight error: \{Repr(err)}")
  } noraise {
    _ => fail("missing present interface accepted")
  }
  try
    @state.evaluate_intent(snapshot, {
      links: [{ name: "missing", ensure: Absent, up: None, mtu: None, }],
      addresses: [],
      routes: [],
    })
  catch {
    @state.StateError::UnsupportedIntent(..) => ()
    err => fail("unexpected absence error: \{Repr(err)}")
  } noraise {
    _ => fail("unsupported link deletion accepted")
  }
}
