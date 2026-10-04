///|
fn done_extack(
  attributes : ArrayView[@core.NetlinkAttribute],
) -> @core.NetlinkMessage raise {
  let payload = [ for byte in b"\x00\x00\x00\x00" => byte ]
  for attribute in attributes {
    for byte in @core.encode_attribute(attribute) {
      payload.push(byte)
    }
  }
  {
    header: {
      length: (16 + payload.length()).reinterpret_as_uint(),
      message_type: 3,
      flags: 0x200,
      sequence: 7,
      port_id: 0,
    },
    payload: Bytes::from_array(payload[:]),
  }
}

///|
test "DONE extack retains cookies missing fields and unknown attributes" {
  let attribute : (UInt16, Bytes) -> @core.NetlinkAttribute = fn(kind, bytes) {
    {
      attribute_type: kind,
      nested: false,
      network_byte_order: false,
      payload: bytes,
    }
  }
  let unknown = attribute(99, b"\x01\x02")
  let message = done_extack([
    attribute(3, b"\x01\xff"),
    attribute(5, b"\x07\x00\x00\x00"),
    attribute(6, b"\x14\x00\x00\x00"),
    unknown,
  ])
  let ack = @core.decode_extended_ack(message).unwrap()
  assert_eq(ack.cookie, Some(b"\x01\xff"))
  assert_eq(ack.missing_type, Some(7))
  assert_eq(ack.missing_nest, Some(20))
  assert_eq(ack.unknown_attributes, [unknown])
  assert_eq(
    @core.decode_extended_ack({
      ..message,
      header: { ..message.header, flags: 0, },
    }),
    None,
  )
}

///|
test "extack rejects invalid UTF8 embedded NUL and non-u32 numeric fields" {
  for bytes in [b"\xff\x00", b"a\x00b\x00", b"missing terminator", b""] {
    let message = done_extack([
      {
        attribute_type: 1,
        nested: false,
        network_byte_order: false,
        payload: bytes,
      },
    ])
    try @core.decode_extended_ack(message) catch {
      InvalidString(..) => ()
      err => fail("unexpected invalid text error: \{Repr(err)}")
    } noraise {
      _ => fail("invalid diagnostic text accepted")
    }
  }
  for kind in [2, 5, 6] {
    let message = done_extack([
      {
        attribute_type: kind.to_uint16(),
        nested: false,
        network_byte_order: false,
        payload: b"\x01",
      },
    ])
    try @core.decode_extended_ack(message) catch {
      UnexpectedFieldLength(..) => ()
      err => fail("unexpected invalid integer error: \{Repr(err)}")
    } noraise {
      _ => fail("short integer accepted")
    }
  }
}

///|
fn extack_message(capped : Bool, success : Bool) -> @core.NetlinkMessage raise {
  let text = @core.encode_attribute({
    attribute_type: 1,
    nested: false,
    network_byte_order: false,
    payload: b"invalid MTU\x00",
  })
  let offset = @core.encode_attribute({
    attribute_type: 2,
    nested: false,
    network_byte_order: false,
    payload: b"\x20\x00\x00\x00",
  })
  let start = if capped || success { 20 } else { 36 }
  let payload = FixedArray::make(
    start + text.length() + offset.length(),
    b'\x00',
  )
  @core.write_u32_le(
    payload,
    0,
    if success {
      0
    } else {
      (-22).reinterpret_as_uint()
    },
  )
  @core.write_u32_le(payload, 4, 32)
  @core.write_u16_le(payload, 8, 16)
  for index, byte in text {
    payload[start + index] = byte
  }
  for index, byte in offset {
    payload[start + text.length() + index] = byte
  }
  {
    header: {
      length: (16 + payload.length()).reinterpret_as_uint(),
      message_type: 2,
      flags: if capped {
        0x300
      } else {
        0x200
      },
      sequence: 7,
      port_id: 0,
    },
    payload: Bytes::from_array(payload[:]),
  }
}

///|
test "extack skips uncapped echoes and decodes capped errors and success warnings" {
  for (capped, success) in [(true, false), (false, false), (false, true)] {
    guard @core.decode_extended_ack(extack_message(capped, success))
      is Some(ack) else {
      fail("expected extack")
    }
    assert_eq(ack.message, Some("invalid MTU"))
    assert_eq(ack.offset, Some(32))
  }
}

///|
test "extack validates malformed attribute lengths and echoed request bounds" {
  let message = extack_message(false, false)
  let payload = message.payload.to_array()
  for index in 4..<8 {
    payload[index] = b'\xff'
  }
  try
    @core.decode_extended_ack({
      ..message,
      payload: Bytes::from_array(payload[:]),
    })
  catch {
    Truncated(..) => ()
    error => fail("unexpected: \{Repr(error)}")
  } noraise {
    _ => fail("huge echo length accepted")
  }
  let capped = extack_message(true, false)
  let invalid = capped.payload.to_array()
  invalid[20] = b'\x00'
  invalid[21] = b'\x00'
  try
    @core.decode_extended_ack({
      ..capped,
      payload: Bytes::from_array(invalid[:]),
    })
  catch {
    InvalidLength(..) => ()
    error => fail("unexpected: \{Repr(error)}")
  } noraise {
    _ => fail("zero extack length accepted")
  }
}
