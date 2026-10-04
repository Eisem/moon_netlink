///|
fn hardware_link(
  hardware_type : UInt16,
  address : Bytes,
) -> @core.NetlinkMessage raise {
  let attribute = @core.encode_attribute({
    attribute_type: 1,
    nested: false,
    network_byte_order: false,
    payload: address,
  })
  let payload = FixedArray::make(16 + attribute.length(), b'\x00')
  @core.write_u16_le(payload, 2, hardware_type)
  @core.write_u32_le(payload, 4, 7)
  for index, byte in attribute {
    payload[16 + index] = byte
  }
  {
    header: {
      length: (16 + payload.length()).reinterpret_as_uint(),
      message_type: @route.rtm_newlink,
      flags: 2,
      sequence: 7,
      port_id: 0,
    },
    payload: Bytes::from_array(payload[:]),
  }
}

///|
test "non-Ethernet hardware addresses are preserved instead of decoded as MAC" {
  let cases : Array[(UInt16, Bytes)] = [
    (768, b"\xc0\x00\x02\x01"), // ARPHRD_TUNNEL: IPv4 endpoint
    (
      32, b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13",
    ),
    (65534, b""), // ARPHRD_NONE
    (512, b"\x00\x01\x02\x03\x04\x05"), // six bytes do not imply Ethernet
  ]
  for (hardware_type, address) in cases {
    let link = @route.decode_link(hardware_link(hardware_type, address))
    assert_eq(link.index, 7)
    assert_eq(link.mac, None)
    assert_eq(link.unknown_attributes.length(), 1)
    assert_eq(link.unknown_attributes[0].attribute_type, 1)
    assert_eq(link.unknown_attributes[0].payload, address)
  }
}

///|
test "Ethernet and loopback still require exactly six MAC bytes" {
  let hardware_types : Array[UInt16] = [1, 772]
  for hardware_type in hardware_types {
    let link = @route.decode_link(
      hardware_link(hardware_type, b"\x00\x01\x02\x03\x04\x05"),
    )
    guard link.mac is Some(mac) else { fail("expected six-byte MAC") }
    assert_eq(mac.to_string(), "00:01:02:03:04:05")
    try
      @route.decode_link(hardware_link(hardware_type, b"\xc0\x00\x02\x01"))
    catch {
      @core.CodecError::UnexpectedFieldLength(context~, length~, expected~) => {
        assert_eq(context, "IFLA_ADDRESS")
        assert_eq(length, 4)
        assert_eq(expected, 6)
      }
      err => fail("unexpected error: \{Repr(err)}")
    } noraise {
      _ => fail("malformed Ethernet MAC must still fail")
    }
  }
}
