///|
test "plan orders dependencies deterministically and exposes reason and danger" {
  let snapshot = @state.NetworkSnapshot::new(
    links=[{ ..test_link(7, "a"), flags: 0, }, test_link(8, "b")],
    addresses=[test_address(7, "2001:db8::1")],
    routes=[test_route(7)],
    neighbors=[],
  )
  let old_address : @state.DesiredAddress = {
    interface: "a",
    ensure: Absent,
    address: @route.IpAddress::parse("2001:db8::1"),
    prefix_length: 64,
    scope: 0,
  }
  let old_route : @state.DesiredRoute = {
    interface: "a",
    ensure: Absent,
    destination: @route.IpAddress::parse("::"),
    prefix_length: 0,
    gateway: None,
    table: 254,
    priority: 1024,
    protocol: 4,
    scope: 0,
  }
  let desired : @state.DesiredState = {
    links: [
      { name: "b", ensure: Present, up: Some(false), mtu: None, },
      { name: "a", ensure: Present, up: Some(true), mtu: Some(1400), },
    ],
    addresses: [
      {
        ..old_address,
        ensure: Present,
        address: @route.IpAddress::parse("2001:db8::2"),
      },
      old_address,
    ],
    routes: [
      {
        ..old_route,
        ensure: Present,
        destination: @route.IpAddress::parse("192.0.2.0"),
        prefix_length: 24,
        table: 1000,
        priority: 42,
        scope: 253,
      },
      old_route,
    ],
  }
  let plan = @state.build_plan(snapshot, desired)
  assert_eq(plan.steps.length(), 7)
  assert_true(plan.steps[0].change is DeleteRoute(..))
  assert_true(plan.steps[1].change is DeleteAddress(..))
  assert_true(plan.steps[2].change is SetMtu(..))
  assert_true(plan.steps[3].change is SetLinkUp(after=true, ..))
  assert_true(plan.steps[4].change is AddAddress(..))
  assert_true(plan.steps[5].change is AddRoute(..))
  assert_true(plan.steps[6].change is SetLinkUp(after=false, ..))
  assert_true(plan.steps[0].dangerous)
  assert_true(plan.steps.all(step => step.reason.length() > 0))
  let reverse : @state.DesiredState = {
    links: desired.links.rev(),
    addresses: desired.addresses.rev(),
    routes: desired.routes.rev(),
  }
  assert_eq(
    plan.to_json().stringify(),
    @state.build_plan(snapshot, reverse).to_json().stringify(),
  )
  assert_eq(snapshot.link_by_name("a").unwrap().flags, 0)
}

///|
test "empty desired state has an empty ordered plan" {
  let snapshot = @state.NetworkSnapshot::new(
    links=[test_link(7, "veth0")],
    addresses=[],
    routes=[],
    neighbors=[],
  )
  assert_eq(
    @state.build_plan(snapshot, { links: [], addresses: [], routes: [], }).steps.length(),
    0,
  )
}
