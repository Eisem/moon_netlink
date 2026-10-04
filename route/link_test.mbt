///|
test "encode RTM_GETLINK request" {
  let request = @route.encode_get_links(42)
  assert_eq(request.length(), 32)
  assert_eq(@core.read_u32_le(request, 0), 32)
  assert_eq(@core.read_u16_le(request, 4), @route.rtm_getlink)
  assert_eq(@core.read_u16_le(request, 6), 0x0301)
  assert_eq(@core.read_u32_le(request, 8), 42)
}

///|
test "encode RTM_GETLINK point query by index" {
  let request = @route.encode_get_link_by_index(43, 7)
  let messages = @core.decode_datagram(request)
  assert_eq(messages.length(), 1)
  let message = messages[0]
  assert_eq(message.header.length, 32)
  assert_eq(message.header.flags, 1)
  assert_eq(message.header.sequence, 43)
  assert_eq(@core.read_i32_le(message.payload, 4), 7)
}

///|
test "encode RTM_GETLINK point query by name" {
  let request = @route.encode_get_link_by_name(44, "eth0")
  let message = @core.decode_datagram(request)[0]
  assert_eq(message.header.flags, 1)
  assert_eq(message.header.sequence, 44)
  assert_eq(@core.read_i32_le(message.payload, 4), 0)
  let attributes = @core.decode_attributes(message.payload, 16)
  assert_eq(attributes.length(), 1)
  assert_eq(attributes[0].attribute_type, 3)
  assert_eq(attributes[0].payload, b"eth0\x00")
}

///|
test "Link point query validates index and name" {
  try @route.encode_get_link_by_index(1, 0) catch {
    InvalidInterfaceIndex(index~) => assert_eq(index, 0)
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected invalid index to fail")
  }
  try @route.encode_get_link_by_name(1, "") catch {
    EmptyInterfaceName => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected empty name to fail")
  }
  try @route.encode_get_link_by_name(1, "bad\u{0000}name") catch {
    InterfaceNameContainsNul => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected embedded NUL to fail")
  }
  try @route.encode_get_link_by_name(1, "interface-name-too-long") catch {
    InterfaceNameTooLong(encoded_length~, maximum~) => {
      assert_eq(encoded_length, 23)
      assert_eq(maximum, 15)
    }
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected long name to fail")
  }
}

///|
fn link_message(payload : Bytes) -> @core.NetlinkMessage {
  {
    header: {
      length: (16 + payload.length()).reinterpret_as_uint(),
      message_type: @route.rtm_newlink,
      flags: 2,
      sequence: 42,
      port_id: 0,
    },
    payload,
  }
}

///|
test "decode typed Link attributes and preserve nested container" {
  let payload : Bytes = [
    0, 0, 1, 0, 7, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, // ifinfomsg
     9, 0, 3, 0, b'e', b't', b'h', b'0', 0, 0, 0, 0, // IFLA_IFNAME
     8, 0, 4, 0, 0xdc, 0x05, 0, 0, // IFLA_MTU=1500
     10, 0, 1, 0, 0x02, 0x00, 0x00, 0x00, 0x00, 0x01, 0, 0, // MAC
     5, 0, 16, 0, 6, 0, 0, 0, // IFLA_OPERSTATE=UP
     8, 0, 10, 0, 2, 0, 0, 0, // IFLA_MASTER=2
     16, 0, 0x12, 0x80, // nested IFLA_LINKINFO
     9, 0, 1, 0, b'v', b'e', b't', b'h', 0, 0, 0, 0, // IFLA_INFO_KIND
     5, 0, 99, 0, 0xff, 0, 0, 0, // unknown attribute
  ]
  let link = @route.decode_link(link_message(payload))
  assert_eq(link.index, 7)
  assert_eq(link.name, Some("eth0"))
  assert_eq(link.kind, Some("veth"))
  assert_eq(link.mtu, Some(1500))
  guard link.mac is Some(mac) else { fail("expected MAC") }
  assert_eq(mac.to_string(), "02:00:00:00:00:01")
  assert_eq(mac.to_bytes(), b"\x02\x00\x00\x00\x00\x01")
  assert_eq(link.operational_state, Some(Up))
  assert_eq(link.master_index, Some(2))
  assert_eq(link.unknown_attributes.length(), 2)
}

///|
test "decode Link rejects invalid fixed-width attribute" {
  let payload : Bytes = [
    0, 0, 1, 0, 7, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 7, 0, 4, 0, 0xdc, 0x05, 0, 0,
  ]
  try @route.decode_link(link_message(payload)) catch {
    UnexpectedFieldLength(context~, length~, expected~) => {
      assert_eq(context, "IFLA_MTU")
      assert_eq(length, 3)
      assert_eq(expected, 4)
    }
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected invalid MTU length to fail")
  }
}

///|
test "decode Link rejects non-NUL interface name" {
  let payload : Bytes = [
    0, 0, 1, 0, 7, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 8, 0, 3, 0, b'e', b't', b'h',
    b'0',
  ]
  try @route.decode_link(link_message(payload)) catch {
    InvalidString(context~) => assert_eq(context, "IFLA_IFNAME")
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected a non-NUL string to fail")
  }
}
