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

///|
test "message encode decode roundtrip normalizes length" {
  let encoded = @core.encode_message({
    header: { length: 0, message_type: 42, flags: 3, sequence: 99, port_id: 7, },
    payload: b"hello",
  })
  assert_eq(encoded.length(), 24)
  let decoded = @core.decode_datagram(encoded)
  assert_eq(decoded.length(), 1)
  assert_eq(decoded[0].header.length, 21)
  assert_eq(decoded[0].header.message_type, 42)
  assert_eq(decoded[0].payload, b"hello")
}

///|
test "attribute flags and unknown type survive roundtrip" {
  let encoded = @core.encode_attribute({
    attribute_type: 0x1234,
    nested: true,
    network_byte_order: true,
    payload: b"abc",
  })
  let attributes = @core.decode_attributes(encoded, 0)
  assert_eq(attributes.length(), 1)
  assert_eq(attributes[0].attribute_type, 0x1234)
  assert_true(attributes[0].nested)
  assert_true(attributes[0].network_byte_order)
  assert_eq(attributes[0].payload, b"abc")
}

///|
test "attribute encoding rejects lengths that do not fit u16" {
  let payload = Bytes::from_array(FixedArray::make(0x1_0000, b'\x00')[:])
  try
    @core.encode_attribute({
      attribute_type: 1,
      nested: false,
      network_byte_order: false,
      payload,
    })
  catch {
    LengthExceedsLimit(context~, length~, maximum~) => {
      assert_eq(context, "attribute")
      assert_eq(length, 0x1_0000 + @core.nla_header_length)
      assert_eq(maximum, 0xffff)
    }
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected oversized attribute to fail")
  }
}

///|
test "attribute encoding rejects flag bits in the base type" {
  try
    @core.encode_attribute({
      attribute_type: 0x8001,
      nested: false,
      network_byte_order: false,
      payload: b"",
    })
  catch {
    InvalidAttributeType(attribute_type~) => assert_eq(attribute_type, 0x8001)
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected an invalid base type to fail")
  }
}

///|
test "decode multiple aligned messages" {
  let bytes : Bytes = [
    17, 0, 0, 0, 16, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, b'a', 0, 0, 0, 20, 0, 0, 0,
    20, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4,
  ]
  let messages = @core.decode_datagram(bytes)
  assert_eq(messages.length(), 2)
  assert_eq(messages[0].payload, b"a")
  assert_eq(messages[1].payload, b"\x01\x02\x03\x04")
}

///|
test "decode rejects zero message length without looping" {
  let bytes : Bytes = [0, 0, 0, 0, 16, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]
  try @core.decode_datagram(bytes) catch {
    InvalidLength(context~, length~, minimum~) => {
      assert_eq(context, "netlink message")
      assert_eq(length, 0)
      assert_eq(minimum, @core.nlmsg_header_length)
    }
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected invalid length to fail")
  }
}

///|
test "decode rejects truncated attribute header" {
  let bytes : Bytes = [1, 2, 3]
  try @core.decode_attributes(bytes, 0) catch {
    Truncated(context~, needed~, available~, ..) => {
      assert_eq(context, "attribute header")
      assert_eq(needed, @core.nla_header_length)
      assert_eq(available, 3)
    }
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected truncated attribute header to fail")
  }
}
