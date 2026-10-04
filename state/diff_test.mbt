///|
test "diff emits only declared unsatisfied fields and ignores unmanaged resources" {
  let snapshot = @state.NetworkSnapshot::new(
    links=[test_link(7, "veth0"), test_link(8, "unmanaged")],
    addresses=[test_address(8, "2001:db8::2")],
    routes=[],
    neighbors=[],
  )
  let desired : @state.DesiredState = {
    links: [
      { name: "veth0", ensure: Present, up: Some(false), mtu: Some(1400), },
    ],
    addresses: [
      {
        interface: "veth0",
        ensure: Present,
        address: @route.IpAddress::parse("2001:db8::1"),
        prefix_length: 64,
        scope: 0,
      },
    ],
    routes: [],
  }
  let changes = @state.diff(snapshot, desired).changes
  assert_eq(changes.length(), 3)
  assert_true(changes.any(change => change is AddAddress(name="veth0", ..)))
  assert_false(changes.any(change => change is DeleteAddress(..)))
  let satisfied = @state.NetworkSnapshot::new(
    links=[
      { ..test_link(7, "veth0"), flags: 0, mtu: Some(1400), },
      test_link(8, "unmanaged"),
    ],
    addresses=[test_address(7, "2001:db8::1"), test_address(8, "2001:db8::2")],
    routes=[],
    neighbors=[],
  )
  assert_eq(@state.diff(satisfied, desired).changes.length(), 0)
}

///|
test "diff preflight rejects implicit route replacement and allows explicit migration" {
  let snapshot = @state.NetworkSnapshot::new(
    links=[test_link(7, "veth0")],
    addresses=[],
    routes=[test_route(7)],
    neighbors=[],
  )
  let old_route : @state.DesiredRoute = {
    interface: "veth0",
    ensure: Absent,
    destination: @route.IpAddress::parse("::"),
    prefix_length: 0,
    gateway: None,
    table: 254,
    priority: 1024,
    protocol: 4,
    scope: 0,
  }
  let new_route = {
    ..old_route,
    ensure: Present,
    gateway: Some(@route.IpAddress::parse("fe80::1")),
  }
  try
    @state.diff(snapshot, { links: [], addresses: [], routes: [new_route], })
  catch {
    @state.StateError::ConflictingIntent(..) => ()
    err => fail("unexpected conflict error: \{Repr(err)}")
  } noraise {
    _ => fail("implicit overwrite accepted")
  }
  let changes = @state.diff(snapshot, {
      links: [],
      addresses: [],
      routes: [old_route, new_route],
    }).changes
  assert_eq(changes.length(), 2)
  assert_true(changes.any(change => change is DeleteRoute(..)))
  assert_true(changes.any(change => change is AddRoute(..)))
  assert_eq(
    @state.diff(snapshot, {
      links: [],
      addresses: [],
      routes: [{ ..old_route, ensure: Present, }],
    }).changes.length(),
    0,
  )
}
