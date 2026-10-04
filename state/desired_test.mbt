///|
test "desired numbers cannot round fractions or underflow into integers" {
  for
    number in [
      "4294967295.0000000001", "1.0000000000000000001", "1e-999", "-0", "1.0", "1e0",
    ] {
    let input = "{\"schema_version\":1,\"routes\":[{\"interface\":\"veth0\",\"ensure\":\"present\",\"destination\":\"192.0.2.0\",\"prefix_length\":24,\"priority\":\{number}}]}"
    try @state.DesiredState::parse(input) catch {
      @state.StateError::InvalidField(..) => ()
      err => fail("unexpected numeric error: \{Repr(err)}")
    } noraise {
      _ => fail("noncanonical integer accepted: \{number}")
    }
  }
  let desired = @state.DesiredState::parse(
    "{\"schema_version\":1,\"links\":[{\"name\":\"veth\\u0031e-0\",\"ensure\":\"present\",\"mtu\":4294967295}],\"routes\":[{\"interface\":\"veth0\",\"ensure\":\"absent\",\"destination\":\"192.0.2.0\",\"prefix_length\":24,\"priority\":0}]}",
  )
  assert_eq(desired.links[0].name, "veth1e-0")
  assert_eq(desired.links[0].mtu, Some(4294967295U))
  assert_eq(desired.routes[0].priority, 0U)
}

///|
test "desired schema parses explicit intent and family-specific defaults" {
  let desired = @state.DesiredState::parse(
    "{\"schema_version\":1,\"routes\":[{\"interface\":\"veth0\",\"ensure\":\"present\",\"destination\":\"2001:db8::\",\"prefix_length\":64}]}",
  )
  assert_eq(desired.routes[0].priority, 1024)
  assert_eq(desired.routes[0].table, 254)
  assert_eq(desired.routes[0].scope, 0)
  assert_eq(desired.links.length(), 0)
}

///|
test "strict desired schema rejects unknown missing fractional and out-of-range fields" {
  for
    input in [
      "{}", "{\"schema_version\":2}", "{\"schema_version\":1,\"surprise\":0}", "{\"schema_version\":1,\"links\":[{\"name\":\"veth0\",\"ensure\":\"present\",\"mtu\":1.5}]}",
      "{\"schema_version\":1,\"links\":[{\"name\":\"veth0\",\"ensure\":\"present\",\"mtu\":4294967296}]}",
      "{\"schema_version\":1,\"links\":[{\"name\":\"veth0\",\"ensure\":\"maybe\"}]}",
    ] {
    try @state.DesiredState::parse(input) catch {
      @state.StateError::InvalidField(..) => ()
      err => fail("unexpected schema error: \{Repr(err)}")
    } noraise {
      _ => fail("invalid desired accepted")
    }
  }
}

///|
test "desired rejects conflicting resource identities host bits and wrong gateway family" {
  let address : @state.DesiredAddress = {
    interface: "veth0",
    ensure: Present,
    address: @route.IpAddress::parse("192.0.2.1"),
    prefix_length: 24,
    scope: 0,
  }
  try
    @state.validate_desired({
      links: [],
      addresses: [address, { ..address, ensure: Absent, }],
      routes: [],
    })
  catch {
    @state.StateError::ConflictingIntent(..) => ()
    err => fail("unexpected conflict error: \{Repr(err)}")
  } noraise {
    _ => fail("conflict accepted")
  }
  for
    (destination, gateway) in [("192.0.2.1", "192.0.2.2"), ("192.0.2.0", "::1")] {
    let route : @state.DesiredRoute = {
      interface: "veth0",
      ensure: Present,
      destination: @route.IpAddress::parse(destination),
      prefix_length: 24,
      gateway: Some(@route.IpAddress::parse(gateway)),
      table: 254,
      priority: 0,
      protocol: 4,
      scope: 0,
    }
    try
      @state.validate_desired({ links: [], addresses: [], routes: [route], })
    catch {
      @route.MutationError::NonCanonicalDestination
      | @route.MutationError::GatewayFamilyMismatch => ()
      err => fail("unexpected route validation error: \{Repr(err)}")
    } noraise {
      _ => fail("invalid route accepted")
    }
  }
}
