///|
test "decode one netlink message" {
  let bytes : Bytes = [
    20, 0, 0, 0, // length
     16, 0, // RTM_NEWLINK
     2, 0, // flags
     7, 0, 0, 0, // sequence
     0, 0, 0, 0, // port id
     1, 2, 3, 4, // payload
  ]
  let messages = @core.decode_datagram(bytes)
  assert_eq(messages.length(), 1)
  assert_eq(messages[0].header.message_type, 16)
  assert_eq(messages[0].header.sequence, 7)
  assert_eq(messages[0].payload, b"\x01\x02\x03\x04")
}

///|
test "decode rejects a truncated message" {
  let bytes : Bytes = [20, 0, 0, 0, 16, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0]
  try @core.decode_datagram(bytes) catch {
    Truncated(context~, needed~, available~, ..) => {
      assert_eq(context, "netlink message")
      assert_eq(needed, 20)
      assert_eq(available, 16)
    }
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected truncated input to fail")
  }
}

///|
test "decode aligned attributes" {
  let bytes : Bytes = [
    7, 0, 3, 0, b'l', b'o', 0, 0, // IFLA_IFNAME plus padding
     8, 0, 4, 0, 0xdc, 0x05, 0, 0, // IFLA_MTU 1500
  ]
  let attributes = @core.decode_attributes(bytes, 0)
  assert_eq(attributes.length(), 2)
  assert_eq(attributes[0].attribute_type, 3)
  assert_eq(attributes[0].payload, b"lo\x00")
  assert_eq(attributes[1].attribute_type, 4)
  assert_eq(@core.read_u32_le(attributes[1].payload, 0), 1500)
}
