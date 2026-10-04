///|
fn address_message(payload : Bytes) -> @core.NetlinkMessage {
  {
    header: {
      length: (16 + payload.length()).reinterpret_as_uint(),
      message_type: @route.rtm_newaddr,
      flags: 2,
      sequence: 51,
      port_id: 0,
    },
    payload,
  }
}

///|
test "encode RTM_GETADDR dump request" {
  let request = @route.encode_get_addresses(50)
  let message = @core.decode_datagram(request)[0]
  assert_eq(message.header.length, 24)
  assert_eq(message.header.message_type, @route.rtm_getaddr)
  assert_eq(message.header.flags, 0x0301)
  assert_eq(message.header.sequence, 50)
  assert_eq(message.payload, b"\x00\x00\x00\x00\x00\x00\x00\x00")
}

///|
test "decode IPv4 address attributes" {
  let payload : Bytes = [
    2, 24, 0x80, 0, 7, 0, 0, 0, // ifaddrmsg
     8, 0, 2, 0, 192, 0, 2, 10, // IFA_LOCAL
     8, 0, 1, 0, 192, 0, 2, 10, // IFA_ADDRESS
     9, 0, 3, 0, b'e', b't', b'h', b'0', 0, 0, 0, 0, // IFA_LABEL
     8, 0, 8, 0, 0x80, 0x01, 0, 0, // IFA_FLAGS overrides header byte
     5, 0, 99, 0, 7, 0, 0, 0, // unknown
  ]
  let address = @route.decode_address(address_message(payload))
  assert_eq(address.family, Ipv4)
  assert_eq(address.interface_index, 7)
  assert_eq(address.interface_name, None)
  assert_eq(address.prefix_length, 24)
  assert_eq(address.scope, 0)
  guard address.local_address is Some(local_address) else {
    fail("expected local address")
  }
  assert_eq(local_address.to_bytes(), b"\xc0\x00\x02\x0a")
  assert_eq(address.address, address.local_address)
  assert_eq(address.label, Some("eth0"))
  assert_eq(address.flags, 0x180)
  assert_eq(address.unknown_attributes.length(), 1)
}

///|
test "decode IPv6 address and reject invalid width" {
  let valid : Bytes = [
    10, 64, 0, 0, 3, 0, 0, 0, 20, 0, 1, 0, 0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 1,
  ]
  let address = @route.decode_address(address_message(valid))
  assert_eq(address.family, Ipv6)
  guard address.address is Some(ip) else { fail("expected IPv6 address") }
  assert_eq(ip.to_bytes().length(), 16)
  let invalid : Bytes = [
    10, 64, 0, 0, 3, 0, 0, 0, 8, 0, 1, 0, 0x20, 0x01, 0x0d, 0xb8,
  ]
  try @route.decode_address(address_message(invalid)) catch {
    UnexpectedFieldLength(context~, length~, expected~) => {
      assert_eq(context, "IFA_ADDRESS")
      assert_eq(length, 4)
      assert_eq(expected, 16)
    }
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected invalid IPv6 width to fail")
  }
}
