///|
test "IPv6 non-octet prefixes and default route encodings validate canonically" {
  let spec : @route.RouteSpec = {
    destination: @route.IpAddress::parse("2001:db8:0:0:8000::"),
    prefix_length: 65,
    gateway: None,
    output_interface: 7,
    table: 254,
    priority: None,
    protocol: 4,
    scope: 0,
  }
  let encoded = @core.decode_datagram(@route.encode_add_route(1, spec))[0]
  assert_eq(@route.decode_route(encoded).destination, Some(spec.destination))
  try
    @route.encode_add_route(1, {
      ..spec,
      destination: @route.IpAddress::parse("2001:db8:0:0:8001::"),
    })
  catch {
    @route.MutationError::NonCanonicalDestination => ()
    err => fail("unexpected prefix error: \{Repr(err)}")
  } noraise {
    _ => fail("IPv6 host bits accepted")
  }
  let default_route = @core.decode_datagram(
      @route.encode_add_route(1, {
        ..spec,
        destination: @route.IpAddress::parse("::"),
        prefix_length: 0,
      }),
    )[0]
  assert_eq(@route.decode_route(default_route).destination_prefix_length, 0)
  try @route.encode_add_route(1, { ..spec, table: 0, }) catch {
    @route.MutationError::InvalidTable(table~) => assert_eq(table, 0)
    err => fail("unexpected table error: \{Repr(err)}")
  } noraise {
    _ => fail("unspecified table accepted")
  }
  try
    @route.encode_add_address(1, {
      interface_index: 7,
      address: spec.destination,
      prefix_length: 129,
      scope: 0,
    })
  catch {
    @route.MutationError::InvalidPrefix(maximum~, ..) => assert_eq(maximum, 128)
    err => fail("unexpected IPv6 prefix error: \{Repr(err)}")
  } noraise {
    _ => fail("invalid IPv6 prefix accepted")
  }
}

///|
test "address mutation modes encode Linux flags and preserve IPv4/IPv6 fields" {
  for (ip, prefix) in [("192.0.2.10", 24), ("2001:db8::10", 64)] {
    let spec : @route.AddressSpec = {
      interface_index: 7,
      address: @route.IpAddress::parse(ip),
      prefix_length: prefix.to_byte(),
      scope: 0,
    }
    for
      (mode, expected) in [(@route.AddMode::Exclusive, 0x605), (Replace, 0x505)] {
      let message = @core.decode_datagram(
          @route.encode_add_address(5, spec, mode~),
        )[0]
      assert_eq(message.header.flags, expected.to_uint16())
      let address = @route.decode_address(message)
      assert_eq(address.interface_index, 7)
      assert_eq(address.local_address, Some(spec.address))
      assert_eq(address.prefix_length, spec.prefix_length)
    }
    let deletion = @core.decode_datagram(@route.encode_delete_address(6, spec))[0]
    assert_eq(deletion.header.message_type, 21)
    assert_eq(deletion.header.flags, 5)
  }
}

///|
test "MTU mutation carries only MTU and leaves interface change mask empty" {
  let message = @core.decode_datagram(@route.encode_set_link_mtu(5, 7, 1400))[0]
  assert_eq(message.header.flags, 5)
  assert_eq(@core.read_u32_le(message.payload, 12), 0)
  let attributes = @core.decode_attributes(message.payload, 16)
  assert_eq(attributes.length(), 1)
  assert_eq(attributes[0].attribute_type, 4)
  assert_eq(@core.read_u32_le(attributes[0].payload, 0), 1400)
}

///|
test "route mutation retains large tables metrics gateway and explicit modes" {
  let spec : @route.RouteSpec = {
    destination: @route.IpAddress::parse("198.51.100.0"),
    prefix_length: 24,
    gateway: Some(@route.IpAddress::parse("192.0.2.1")),
    output_interface: 7,
    table: 1000,
    priority: Some(42),
    protocol: 4,
    scope: 0,
  }
  let message = @core.decode_datagram(@route.encode_add_route(8, spec))[0]
  let route = @route.decode_route(message)
  assert_eq(message.header.flags, 0x605)
  assert_eq(route.table, 1000)
  assert_eq(route.priority, Some(42))
  assert_eq(route.gateway, spec.gateway)
  assert_eq(route.destination_prefix_length, 24)
  assert_eq(
    @core.decode_datagram(@route.encode_add_route(8, spec, mode=Replace))[0].header.flags,
    0x505,
  )
  let deletion = @core.decode_datagram(@route.encode_delete_route(8, spec))[0]
  assert_eq(deletion.header.message_type, 25)
  assert_eq(deletion.header.flags, 5)
}

///|
test "mutation validation rejects invalid prefixes host bits and family mismatch" {
  let spec : @route.RouteSpec = {
    destination: @route.IpAddress::parse("192.0.2.0"),
    prefix_length: 24,
    gateway: None,
    output_interface: 7,
    table: 254,
    priority: None,
    protocol: 4,
    scope: 253,
  }
  try @route.encode_add_route(1, { ..spec, prefix_length: 33, }) catch {
    @route.MutationError::InvalidPrefix(maximum~, ..) => assert_eq(maximum, 32)
    error => fail("unexpected: \{Repr(error)}")
  } noraise {
    _ => fail("invalid prefix accepted")
  }
  try
    @route.encode_add_route(1, {
      ..spec,
      destination: @route.IpAddress::parse("192.0.2.1"),
    })
  catch {
    @route.MutationError::NonCanonicalDestination => ()
    error => fail("unexpected: \{Repr(error)}")
  } noraise {
    _ => fail("host bits accepted")
  }
  try
    @route.encode_add_route(1, {
      ..spec,
      gateway: Some(@route.IpAddress::parse("::1")),
    })
  catch {
    @route.MutationError::GatewayFamilyMismatch => ()
    error => fail("unexpected: \{Repr(error)}")
  } noraise {
    _ => fail("mismatched gateway accepted")
  }
  try @route.encode_set_link_mtu(1, 1, 0) catch {
    @route.MutationError::InvalidMtu(mtu~) => assert_eq(mtu, 0)
    error => fail("unexpected: \{Repr(error)}")
  } noraise {
    _ => fail("zero MTU accepted")
  }
}
