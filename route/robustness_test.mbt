///|
test "robustness: seed 0x4d4e4c33 preserves 256 reordered typed Link attributes and rejects malformed nesting" {
  let mut seed : UInt = 0x4d4e4c33
  for iteration in 0..<256 {
    seed = seed ^ (seed << 13)
    seed = seed ^ (seed >> 17)
    seed = seed ^ (seed << 5)
    let mtu = 1280U + seed % 7721
    let mtu_bytes = FixedArray::make(4, b'\x00')
    @core.write_u32_le(mtu_bytes, 0, mtu)
    let unknown : @core.NetlinkAttribute = {
      attribute_type: (0x1000U + seed % 0x1000).to_uint16(),
      nested: false,
      network_byte_order: (seed & 1) != 0,
      payload: b"\x01\x02\x03",
    }
    let attributes : Array[@core.NetlinkAttribute] = [
      {
        attribute_type: 3,
        nested: false,
        network_byte_order: false,
        payload: b"veth0\x00",
      },
      {
        attribute_type: 4,
        nested: false,
        network_byte_order: false,
        payload: Bytes::from_array(mtu_bytes[:]),
      },
      {
        attribute_type: 18,
        nested: true,
        network_byte_order: false,
        payload: @core.encode_attribute({
          attribute_type: 1,
          nested: false,
          network_byte_order: false,
          payload: b"veth\x00",
        }),
      },
      unknown,
    ]
    for index = attributes.length() - 1; index > 0; index = index - 1 {
      let other = ((seed >> (index * 3)) % (index + 1).reinterpret_as_uint()).reinterpret_as_int()
      let saved = attributes[index]
      attributes[index] = attributes[other]
      attributes[other] = saved
    }
    let body : Array[Byte] = [0, 0, 1, 0, 7, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]
    for attribute in attributes {
      for byte in @core.encode_attribute(attribute) {
        body.push(byte)
      }
    }
    let link = @route.decode_link(link_message(Bytes::from_array(body[:])))
    assert_eq(
      link.name,
      Some("veth0"),
      msg="seed=0x4d4e4c33 iteration=\{iteration}",
    )
    assert_eq(link.kind, Some("veth"))
    assert_eq(link.mtu, Some(mtu))
    assert_eq(link.unknown_attributes.filter(a => a.attribute_type >= 0x1000), [
      unknown,
    ])
    let nested = @core.encode_attribute({
      attribute_type: 18,
      nested: true,
      network_byte_order: false,
      payload: Bytes::from_array([(seed % 4).to_byte(), 0, 1, 0]),
    })
    let malformed : Array[Byte] = [
      0, 0, 1, 0, 7, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
    ]
    for byte in nested {
      malformed.push(byte)
    }
    try
      @route.decode_link(link_message(Bytes::from_array(malformed[:])))
    catch {
      InvalidLength(context~, ..) => assert_eq(context, "attribute")
      error => fail("seed=0x4d4e4c33 iteration=\{iteration}: \{Repr(error)}")
    } noraise {
      _ => fail("malformed nesting accepted at iteration \{iteration}")
    }
  }
}
