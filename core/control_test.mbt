///|
fn control_message(
  message_type : UInt16,
  payload : Bytes,
) -> @core.NetlinkMessage {
  {
    header: {
      length: (16 + payload.length()).reinterpret_as_uint(),
      message_type,
      flags: 0,
      sequence: 7,
      port_id: 0,
    },
    payload,
  }
}

///|
fn nlmsgerr_payload(errno : Int) -> Bytes {
  let buffer = FixedArray::make(20, b'\x00')
  @core.write_u32_le(buffer, 0, errno.reinterpret_as_uint())
  @core.write_u32_le(buffer, 4, 32)
  @core.write_u16_le(buffer, 8, 18)
  @core.write_u16_le(buffer, 10, 0x301)
  @core.write_u32_le(buffer, 12, 7)
  @core.write_u32_le(buffer, 16, 0)
  Bytes::from_array(buffer[:])
}

///|
test "decode ACK distinguishes zero errno" {
  let control = @core.decode_control(
    control_message(@core.nlmsg_error, nlmsgerr_payload(0)),
  )
  guard control is Some(Ack(header)) else { fail("expected ACK") }
  assert_eq(header.message_type, 18)
  assert_eq(header.sequence, 7)
}

///|
test "decode kernel error normalizes negative errno" {
  let control = @core.decode_control(
    control_message(@core.nlmsg_error, nlmsgerr_payload(-22)),
  )
  guard control is Some(KernelError(errno, header)) else {
    fail("expected kernel error")
  }
  assert_eq(errno, 22)
  assert_eq(header.length, 32)
}

///|
test "decode DONE with and without status" {
  assert_eq(
    @core.decode_control(control_message(@core.nlmsg_done, b"")),
    Some(Done(None)),
  )
  let status = FixedArray::make(4, b'\x00')
  @core.write_u32_le(status, 0, (-4).reinterpret_as_uint())
  assert_eq(
    @core.decode_control(
      control_message(@core.nlmsg_done, Bytes::from_array(status[:])),
    ),
    Some(Done(Some(-4))),
  )
}

///|
test "decode malformed error is structured truncation" {
  try
    @core.decode_control(
      control_message(@core.nlmsg_error, b"\x00\x00\x00\x00"),
    )
  catch {
    Truncated(context~, needed~, available~, ..) => {
      assert_eq(context, "nlmsgerr")
      assert_eq(needed, 20)
      assert_eq(available, 4)
    }
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected malformed nlmsgerr to fail")
  }
}
