///|
fn neighbor_message(payload : Bytes) -> @core.NetlinkMessage {
  {
    header: {
      length: (16 + payload.length()).reinterpret_as_uint(),
      message_type: @route.rtm_newneigh,
      flags: 2,
      sequence: 71,
      port_id: 0,
    },
    payload,
  }
}

///|
test "encode RTM_GETNEIGH dump request" {
  let request = @route.encode_get_neighbors(70)
  let message = @core.decode_datagram(request)[0]
  assert_eq(message.header.length, 28)
  assert_eq(message.header.message_type, @route.rtm_getneigh)
  assert_eq(message.header.flags, 0x0301)
  assert_eq(message.header.sequence, 70)
  assert_eq(message.payload.length(), 12)
}

///|
test "decode IPv4 neighbor attributes" {
  let payload : Bytes = [
    2, 0, 0, 0, 7, 0, 0, 0, 2, 0, 0x80, 1, // ndmsg
     8, 0, 1, 0, 192, 0, 2, 1, // NDA_DST
     10, 0, 2, 0, 0x02, 0x42, 0xac, 0x11, 0, 2, 0, 0, // NDA_LLADDR
     8, 0, 4, 0, 3, 0, 0, 0, // NDA_PROBES
     5, 0, 99, 0, 7, 0, 0, 0, // unknown
  ]
  let neighbor = @route.decode_neighbor(neighbor_message(payload))
  assert_eq(neighbor.family, Ipv4)
  assert_eq(neighbor.interface_index, 7)
  assert_eq(neighbor.interface_name, None)
  guard neighbor.destination is Some(destination) else {
    fail("expected destination")
  }
  assert_eq(destination.to_string(), "192.0.2.1")
  guard neighbor.link_layer_address is Some(mac) else {
    fail("expected link-layer address")
  }
  assert_eq(mac.to_string(), "02:42:ac:11:00:02")
  assert_eq(neighbor.state, Reachable)
  assert_eq(neighbor.flags, 0x80)
  assert_eq(neighbor.neighbor_type, 1)
  assert_eq(neighbor.probes, Some(3))
  assert_eq(neighbor.unknown_attributes.length(), 1)
}

///|
test "decode IPv6 neighbor and reject malformed link-layer address" {
  let valid : Bytes = [
    10, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 1, 20, 0, 1, 0, 0xfe, 0x80, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 1,
  ]
  let neighbor = @route.decode_neighbor(neighbor_message(valid))
  assert_eq(neighbor.family, Ipv6)
  assert_eq(neighbor.state, Stale)
  guard neighbor.destination is Some(destination) else {
    fail("expected destination")
  }
  assert_eq(destination.to_string(), "fe80::1")
  let invalid : Bytes = [
    2, 0, 0, 0, 7, 0, 0, 0, 2, 0, 0, 1, 9, 0, 2, 0, 1, 2, 3, 4, 5, 0, 0, 0,
  ]
  try @route.decode_neighbor(neighbor_message(invalid)) catch {
    UnexpectedFieldLength(context~, length~, expected~) => {
      assert_eq(context, "NDA_LLADDR")
      assert_eq(length, 5)
      assert_eq(expected, 6)
    }
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected malformed MAC width to fail")
  }
}
