///|
test "normalization is deterministic resolves names and does not mutate input" {
  let a : @route.Link = {
    index: 7,
    name: Some("a"),
    kind: None,
    mtu: Some(1500),
    mac: None,
    flags: 0,
    operational_state: None,
    master_index: None,
    unknown_attributes: [],
  }
  let b = { ..a, index: 8, name: Some("b"), }
  let address : @route.Address = {
    family: Ipv6,
    interface_index: 7,
    interface_name: Some("stale"),
    prefix_length: 64,
    scope: 0,
    local_address: None,
    address: Some(@route.IpAddress::parse("2001:db8::1")),
    label: None,
    flags: 64,
    unknown_attributes: [],
  }
  let first = @state.NetworkSnapshot::new(
    links=[b, a],
    addresses=[address],
    routes=[],
    neighbors=[],
  )
  let second = @state.NetworkSnapshot::new(
    links=[a, b],
    addresses=[address],
    routes=[],
    neighbors=[],
  )
  assert_eq(first.to_json().stringify(), second.to_json().stringify())
  assert_eq(@state.normalize(first).addresses[0].interface_name, Some("a"))
  assert_eq(first.addresses[0].interface_name, Some("stale"))
  assert_eq(@state.normalize(@state.normalize(first)), @state.normalize(first))
  let changed = @state.NetworkSnapshot::new(
    links=[a, { ..b, mtu: Some(1400), }],
    addresses=[],
    routes=[],
    neighbors=[],
  )
  assert_true(first.to_json() != changed.to_json())
}
