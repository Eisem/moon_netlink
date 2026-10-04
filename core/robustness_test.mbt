///|
struct RobustRng {
  mut value : UInt
}

///|
fn RobustRng::next(self : RobustRng) -> UInt {
  let mut value = self.value
  value = value ^ (value << 13)
  value = value ^ (value >> 17)
  value = value ^ (value << 5)
  self.value = value
  value
}

///|
fn RobustRng::bounded(self : RobustRng, limit : Int) -> Int {
  (self.next() % limit.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn RobustRng::payload(self : RobustRng, length : Int) -> Bytes {
  Bytes::from_array(FixedArray::makei(length, _ => self.next().to_byte())[:])
}

///|
fn robust_attribute_bytes(
  attributes : Array[@core.NetlinkAttribute],
) -> Bytes raise {
  let bytes : Array[Byte] = []
  for attribute in attributes {
    for byte in @core.encode_attribute(attribute) {
      bytes.push(byte)
    }
  }
  Bytes::from_array(bytes[:])
}

///|
test "robustness: seed 0x4d4e4c31 preserves 512 shuffled unknown and nested attribute chains" {
  let rng : RobustRng = { value: 0x4d4e4c31, }
  for iteration in 0..<512 {
    let attributes : Array[@core.NetlinkAttribute] = []
    for index in 0..<(1 + rng.bounded(16)) {
      let nested = rng.bounded(3) == 0
      let payload = rng.payload(rng.bounded(32))
      attributes.push({
        attribute_type: (0x1000 + index).to_uint16(),
        nested,
        network_byte_order: rng.bounded(2) == 1,
        payload: if nested {
          @core.encode_attribute({
            attribute_type: 0x2000,
            nested: false,
            network_byte_order: false,
            payload,
          })
        } else {
          payload
        },
      })
    }
    for index = attributes.length() - 1; index > 0; index = index - 1 {
      let other = rng.bounded(index + 1)
      let saved = attributes[index]
      attributes[index] = attributes[other]
      attributes[other] = saved
    }
    let decoded = @core.decode_attributes(robust_attribute_bytes(attributes), 0)
    assert_eq(decoded, attributes, msg="seed=0x4d4e4c31 iteration=\{iteration}")
    for attribute in decoded {
      if attribute.nested {
        let children = @core.decode_attributes(attribute.payload, 0)
        assert_eq(children.length(), 1)
        assert_eq(children[0].attribute_type, 0x2000)
      }
    }
  }
}

///|
fn reject_robust_message(data : BytesView, iteration : Int) -> Unit raise {
  try @core.decode_datagram(data) catch {
    Truncated(..) | InvalidLength(..) | LengthTooLarge(..) => ()
    error => fail("seed=0x4d4e4c32 iteration=\{iteration}: \{Repr(error)}")
  } noraise {
    _ =>
      fail("seed=0x4d4e4c32 iteration=\{iteration}: malformed message accepted")
  }
}

///|
test "robustness: seed 0x4d4e4c32 rejects 512 generated truncations and corrupt lengths" {
  let rng : RobustRng = { value: 0x4d4e4c32, }
  for iteration in 0..<512 {
    let payload = rng.payload(1 + rng.bounded(128))
    let encoded = @core.encode_message({
      header: {
        length: 0,
        message_type: 99,
        flags: 0,
        sequence: rng.next(),
        port_id: 0,
      },
      payload,
    })
    let wire_length = 16 + payload.length()
    let cut = 1 + rng.bounded(wire_length - 1)
    reject_robust_message(encoded[:cut], iteration)
    for
      length in [
        rng.bounded(16).reinterpret_as_uint(),
        (encoded.length() + 1).reinterpret_as_uint(),
        0xffff_ffff,
      ] {
      let corrupted = FixedArray::makei(encoded.length(), index => {
        encoded[index]
      })
      @core.write_u32_le(corrupted, 0, length)
      reject_robust_message(Bytes::from_array(corrupted[:]), iteration)
    }
    let attribute = @core.encode_attribute({
      attribute_type: 0x1234,
      nested: false,
      network_byte_order: false,
      payload,
    })
    let cut = 1 + rng.bounded(4 + payload.length() - 1)
    try @core.decode_attributes(attribute[:cut], 0) catch {
      Truncated(..) => ()
      error => fail("seed=0x4d4e4c32 iteration=\{iteration}: \{Repr(error)}")
    } noraise {
      _ =>
        fail(
          "seed=0x4d4e4c32 iteration=\{iteration}: truncated attribute accepted",
        )
    }
    let malformed = FixedArray::makei(attribute.length(), index => {
      attribute[index]
    })
    @core.write_u16_le(malformed, 0, rng.bounded(4).to_uint16())
    try @core.decode_attributes(Bytes::from_array(malformed[:]), 0) catch {
      InvalidLength(..) => ()
      error => fail("unexpected attribute length error: \{Repr(error)}")
    } noraise {
      _ => fail("invalid attribute length accepted at iteration \{iteration}")
    }
  }
}
