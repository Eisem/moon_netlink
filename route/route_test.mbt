///|
fn route_message(payload : Bytes) -> @core.NetlinkMessage {
  {
    header: {
      length: (16 + payload.length()).reinterpret_as_uint(),
      message_type: @route.rtm_newroute,
      flags: 2,
      sequence: 61,
      port_id: 0,
    },
    payload,
  }
}

///|
test "encode RTM_GETROUTE dump request" {
  let request = @route.encode_get_routes(60)
  let message = @core.decode_datagram(request)[0]
  assert_eq(message.header.length, 28)
  assert_eq(message.header.message_type, @route.rtm_getroute)
  assert_eq(message.header.flags, 0x0301)
  assert_eq(message.header.sequence, 60)
  assert_eq(message.payload.length(), 12)
}

///|
test "decode IPv4 default route attributes" {
  let payload : Bytes = [
    2, 0, 0, 0, 254, 3, 0, 1, 0x10, 0, 0, 0, // rtmsg
     8, 0, 5, 0, 192, 0, 2, 1, // RTA_GATEWAY
     8, 0, 4, 0, 7, 0, 0, 0, // RTA_OIF
     8, 0, 6, 0, 100, 0, 0, 0, // RTA_PRIORITY
     8, 0, 15, 0, 0xe8, 0x03, 0, 0, // RTA_TABLE=1000
     8, 0, 7, 0, 192, 0, 2, 10, // RTA_PREFSRC
     5, 0, 99, 0, 1, 0, 0, 0, // unknown
  ]
  let route = @route.decode_route(route_message(payload))
  assert_eq(route.family, Ipv4)
  assert_eq(route.destination, None)
  assert_eq(route.destination_prefix_length, 0)
  guard route.gateway is Some(gateway) else { fail("expected gateway") }
  assert_eq(gateway.to_bytes(), b"\xc0\x00\x02\x01")
  assert_eq(route.output_interface, Some(7))
  assert_eq(route.table, 1000)
  assert_eq(route.priority, Some(100))
  assert_eq(route.protocol, 3)
  assert_eq(route.scope, 0)
  assert_eq(route.route_type, 1)
  assert_eq(route.flags, 0x10)
  assert_eq(route.unknown_attributes.length(), 1)
}

///|
test "decode IPv6 route and reject malformed index" {
  let valid : Bytes = [
    10, 64, 0, 0, 254, 4, 0, 1, 0, 0, 0, 0, 20, 0, 1, 0, 0x20, 0x01, 0x0d, 0xb8,
    0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 20, 0, 5, 0, 0xfe, 0x80, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 1,
  ]
  let route = @route.decode_route(route_message(valid))
  assert_eq(route.family, Ipv6)
  assert_eq(route.destination_prefix_length, 64)
  guard route.destination is Some(destination) else {
    fail("expected destination")
  }
  assert_eq(destination.to_bytes().length(), 16)
  let invalid : Bytes = [
    2, 0, 0, 0, 254, 3, 0, 1, 0, 0, 0, 0, 7, 0, 4, 0, 1, 0, 0, 0,
  ]
  try @route.decode_route(route_message(invalid)) catch {
    UnexpectedFieldLength(context~, length~, expected~) => {
      assert_eq(context, "RTA_OIF")
      assert_eq(length, 3)
      assert_eq(expected, 4)
    }
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected malformed output interface to fail")
  }
}
