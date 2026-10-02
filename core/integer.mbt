///|
fn require_range(
  data : BytesView,
  offset : Int,
  length : Int,
  context : String,
) -> Unit raise CodecError {
  if offset < 0 || length < 0 {
    raise InvalidOffset(context~, offset~)
  }
  let available = data.length() - offset
  if offset > data.length() || available < length {
    raise Truncated(
      context~,
      offset~,
      needed=length,
      available=if available < 0 { 0 } else { available },
    )
  }
}

///|
/// Read a native-Linux little-endian 16-bit integer after checking bounds.
pub fn read_u16_le(data : BytesView, offset : Int) -> UInt16 raise CodecError {
  require_range(data, offset, 2, "u16")
  let low = data[offset].to_uint16()
  let high = data[offset + 1].to_uint16() << 8
  low | high
}

///|
/// Read a native-Linux little-endian 32-bit integer after checking bounds.
pub fn read_u32_le(data : BytesView, offset : Int) -> UInt raise CodecError {
  require_range(data, offset, 4, "u32")
  data[offset].to_uint() |
  (data[offset + 1].to_uint() << 8) |
  (data[offset + 2].to_uint() << 16) |
  (data[offset + 3].to_uint() << 24)
}

///|
/// Read a signed 32-bit field encoded with the Linux native ABI.
pub fn read_i32_le(data : BytesView, offset : Int) -> Int raise CodecError {
  read_u32_le(data, offset).reinterpret_as_int()
}

///|
/// Write a little-endian 16-bit integer into an already-sized buffer.
pub fn write_u16_le(
  buffer : FixedArray[Byte],
  offset : Int,
  value : UInt16,
) -> Unit {
  buffer[offset] = value.to_byte()
  buffer[offset + 1] = (value >> 8).to_byte()
}

///|
/// Write a little-endian 32-bit integer into an already-sized buffer.
pub fn write_u32_le(
  buffer : FixedArray[Byte],
  offset : Int,
  value : UInt,
) -> Unit {
  buffer[offset] = value.to_byte()
  buffer[offset + 1] = (value >> 8).to_byte()
  buffer[offset + 2] = (value >> 16).to_byte()
  buffer[offset + 3] = (value >> 24).to_byte()
}

///|
/// Return the Netlink four-byte aligned size.
pub fn align4(length : Int) -> Int {
  (length + 3) / 4 * 4
}
