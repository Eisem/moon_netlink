///|
test "encode acknowledged Link UP and DOWN requests" {
  let up = @core.decode_datagram(@route.encode_set_link_state(44, 7, true))[0]
  assert_eq(up.header.length, 32)
  assert_eq(up.header.message_type, @route.rtm_newlink)
  assert_eq(up.header.flags, 0x0005)
  assert_eq(up.header.sequence, 44)
  assert_eq(@core.read_i32_le(up.payload, 4), 7)
  assert_eq(@core.read_u32_le(up.payload, 8), 1)
  assert_eq(@core.read_u32_le(up.payload, 12), 1)
  let down = @core.decode_datagram(@route.encode_set_link_state(45, 7, false))[0]
  assert_eq(down.header.flags, 0x0005)
  assert_eq(@core.read_u32_le(down.payload, 8), 0)
  assert_eq(@core.read_u32_le(down.payload, 12), 1)
}

///|
test "reject non-positive Link state interface index" {
  try @route.encode_set_link_state(46, 0, true) catch {
    InvalidInterfaceIndex(index~) => assert_eq(index, 0)
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected invalid interface index")
  }
}
