///|
/// De-identified, deterministic Linux UAPI fixtures. Unlike the focused
/// field tests, these begin at the complete Netlink header and therefore
/// exercise datagram framing and the typed decoder together.
test "RTM_NEWADDR wire fixture decodes and round-trips" {
  let fixture : Bytes = [
    0x28, 0, 0, 0, 0x14, 0, 2, 0, 0x51, 0x14, 0, 0, 0, 0, 0, 0, 2, 24, 0, 0, 7, 0,
    0, 0, 8, 0, 2, 0, 192, 0, 2, 10, 8, 0, 1, 0, 192, 0, 2, 10,
  ]
  let messages = @core.decode_datagram(fixture)
  assert_eq(messages.length(), 1)
  let address = @route.decode_address(messages[0])
  assert_eq(address.interface_index, 7)
  assert_eq(address.prefix_length, 24)
  guard address.local_address is Some(local_address) else {
    fail("expected fixture local address")
  }
  assert_eq(local_address.to_string(), "192.0.2.10")
  assert_eq(@core.encode_message(messages[0]), fixture)
}

///|
test "RTM_NEWROUTE wire fixture decodes and round-trips" {
  let fixture : Bytes = [
    0x2c, 0, 0, 0, 0x18, 0, 2, 0, 0x39, 0x18, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 254,
    3, 0, 1, 0, 0, 0, 0, 8, 0, 5, 0, 192, 0, 2, 1, 8, 0, 4, 0, 7, 0, 0, 0,
  ]
  let messages = @core.decode_datagram(fixture)
  assert_eq(messages.length(), 1)
  let route = @route.decode_route(messages[0])
  assert_eq(route.destination, None)
  assert_eq(route.destination_prefix_length, 0)
  guard route.gateway is Some(gateway) else { fail("expected fixture gateway") }
  assert_eq(gateway.to_string(), "192.0.2.1")
  assert_eq(route.output_interface, Some(7))
  assert_eq(@core.encode_message(messages[0]), fixture)
}

///|
test "RTM_NEWNEIGH wire fixture decodes and round-trips" {
  let fixture : Bytes = [
    0x30, 0, 0, 0, 0x1c, 0, 2, 0, 0x21, 0x1c, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 7, 0,
    0, 0, 2, 0, 0, 1, 8, 0, 1, 0, 192, 0, 2, 1, 10, 0, 2, 0, 0x02, 0x42, 0xac, 0x11,
    0, 2, 0, 0,
  ]
  let messages = @core.decode_datagram(fixture)
  assert_eq(messages.length(), 1)
  let neighbor = @route.decode_neighbor(messages[0])
  assert_eq(neighbor.interface_index, 7)
  assert_eq(neighbor.state, Reachable)
  guard neighbor.destination is Some(destination) else {
    fail("expected fixture destination")
  }
  assert_eq(destination.to_string(), "192.0.2.1")
  guard neighbor.link_layer_address is Some(mac) else {
    fail("expected fixture MAC")
  }
  assert_eq(mac.to_string(), "02:42:ac:11:00:02")
  assert_eq(@core.encode_message(messages[0]), fixture)
}
