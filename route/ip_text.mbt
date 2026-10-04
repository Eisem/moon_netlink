///|
fn hex_value(value : Int) -> Int? {
  if value >= 48 && value <= 57 {
    Some(value - 48)
  } else if value >= 65 && value <= 70 {
    Some(value - 65 + 10)
  } else if value >= 97 && value <= 102 {
    Some(value - 97 + 10)
  } else {
    None
  }
}

///|
fn parse_decimal_byte(token : StringView) -> Int? {
  if token.length() == 0 || (token.length() > 1 && token[0].to_int() == 48) {
    return None
  }
  let mut value = 0
  for unit in token {
    let digit = unit.to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    value = value * 10 + digit
    if value > 255 {
      return None
    }
  }
  Some(value)
}

///|
fn parse_ipv4_values(input : String) -> Array[Int]? {
  let tokens = input.split(".").to_array()
  if tokens.length() != 4 {
    return None
  }
  let values : Array[Int] = []
  for token in tokens {
    guard parse_decimal_byte(token) is Some(value) else { return None }
    values.push(value)
  }
  Some(values)
}

///|
/// Parse strict dotted-decimal IPv4. Leading zeroes and abbreviated forms are
/// rejected to avoid octal and component-count ambiguity.
pub fn Ipv4Address::parse(
  input : String,
) -> Ipv4Address raise AddressParseError {
  guard parse_ipv4_values(input) is Some(values) else {
    raise InvalidIpv4(input~)
  }
  let bytes = FixedArray::make(4, b'\x00')
  for index, value in values {
    bytes[index] = value.to_byte()
  }
  { bytes: Bytes::from_array(bytes[:]), }
}

///|
fn parse_hex_group(token : StringView) -> Int? {
  if token.length() == 0 || token.length() > 4 {
    return None
  }
  let mut value = 0
  for unit in token {
    guard hex_value(unit.to_int()) is Some(digit) else { return None }
    value = (value << 4) | digit
  }
  Some(value)
}

///|
fn parse_ipv6_side(side : StringView, allow_ipv4_tail : Bool) -> Array[Int]? {
  let groups : Array[Int] = []
  if side.length() == 0 {
    return Some(groups)
  }
  let tokens = side.to_owned().split(":").to_array()
  for index, token in tokens {
    if token.length() == 0 {
      return None
    }
    if token.to_owned().contains_code_unit(46) {
      if !allow_ipv4_tail || index + 1 != tokens.length() {
        return None
      }
      guard parse_ipv4_values(token.to_owned()) is Some(values) else {
        return None
      }
      groups.push((values[0] << 8) | values[1])
      groups.push((values[2] << 8) | values[3])
    } else {
      guard parse_hex_group(token) is Some(value) else { return None }
      groups.push(value)
    }
  }
  Some(groups)
}

///|
/// Parse IPv6 with one optional `::` compression and an optional final
/// dotted-decimal IPv4 component.
pub fn Ipv6Address::parse(
  input : String,
) -> Ipv6Address raise AddressParseError {
  if input.length() == 0 {
    raise InvalidIpv6(input~)
  }
  let compressed = input.split("::").to_array()
  if compressed.length() > 2 {
    raise InvalidIpv6(input~)
  }
  let left_text = compressed[0]
  let right_text = if compressed.length() == 2 { compressed[1] } else { ""[:] }
  guard parse_ipv6_side(left_text, compressed.length() == 1) is Some(left) else {
    raise InvalidIpv6(input~)
  }
  guard parse_ipv6_side(right_text, compressed.length() == 2) is Some(right) else {
    raise InvalidIpv6(input~)
  }
  let present = left.length() + right.length()
  let missing = if compressed.length() == 2 { 8 - present } else { 0 }
  if (compressed.length() == 1 && present != 8) ||
    (compressed.length() == 2 && missing < 1) {
    raise InvalidIpv6(input~)
  }
  let groups : Array[Int] = []
  for value in left {
    groups.push(value)
  }
  for _ in 0..<missing {
    groups.push(0)
  }
  for value in right {
    groups.push(value)
  }
  if groups.length() != 8 {
    raise InvalidIpv6(input~)
  }
  let bytes = FixedArray::make(16, b'\x00')
  for index, value in groups {
    bytes[index * 2] = (value >> 8).to_byte()
    bytes[index * 2 + 1] = value.to_byte()
  }
  { bytes: Bytes::from_array(bytes[:]), }
}

///|
/// Parse either IPv4 or IPv6 according to the presence of a colon.
pub fn IpAddress::parse(input : String) -> IpAddress raise AddressParseError {
  if input.contains_code_unit(58) {
    V6(Ipv6Address::parse(input))
  } else {
    V4(Ipv4Address::parse(input))
  }
}

///|
pub fn Ipv4Address::to_string(self : Ipv4Address) -> String {
  let parts : Array[String] = []
  for byte in self.bytes {
    parts.push(byte.to_int().to_string())
  }
  parts.join(".")
}

///|
/// Format RFC 5952-style lower-case IPv6, compressing the first longest run
/// of at least two zero groups.
pub fn Ipv6Address::to_string(self : Ipv6Address) -> String {
  let groups : Array[Int] = []
  for index in 0..<8 {
    groups.push(
      (self.bytes[index * 2].to_int() << 8) | self.bytes[index * 2 + 1].to_int(),
    )
  }
  let mut best_start = -1
  let mut best_length = 0
  let mut index = 0
  while index < 8 {
    if groups[index] != 0 {
      index = index + 1
      continue
    }
    let start = index
    while index < 8 && groups[index] == 0 {
      index = index + 1
    }
    let length = index - start
    if length >= 2 && length > best_length {
      best_start = start
      best_length = length
    }
  }
  let before : Array[String] = []
  let after : Array[String] = []
  if best_start < 0 {
    for value in groups {
      before.push(value.to_string(radix=16))
    }
    return before.join(":")
  }
  for group_index in 0..<best_start {
    before.push(groups[group_index].to_string(radix=16))
  }
  for group_index in (best_start + best_length)..<8 {
    after.push(groups[group_index].to_string(radix=16))
  }
  if before.length() == 0 && after.length() == 0 {
    "::"
  } else if before.length() == 0 {
    "::" + after.join(":")
  } else if after.length() == 0 {
    before.join(":") + "::"
  } else {
    before.join(":") + "::" + after.join(":")
  }
}

///|
pub fn IpAddress::to_string(self : IpAddress) -> String {
  match self {
    V4(address) => address.to_string()
    V6(address) => address.to_string()
  }
}

///|
/// Parse canonical six-octet colon-separated MAC text. Each octet must use
/// exactly two hexadecimal digits.
pub fn MacAddress::parse(input : String) -> MacAddress raise AddressParseError {
  let tokens = input.split(":").to_array()
  if tokens.length() != 6 {
    raise InvalidMac(input~)
  }
  let bytes = FixedArray::make(6, b'\x00')
  for index, token in tokens {
    if token.length() != 2 {
      raise InvalidMac(input~)
    }
    guard hex_value(token[0].to_int()) is Some(high) else {
      raise InvalidMac(input~)
    }
    guard hex_value(token[1].to_int()) is Some(low) else {
      raise InvalidMac(input~)
    }
    bytes[index] = ((high << 4) | low).to_byte()
  }
  { bytes: Bytes::from_array(bytes[:]), }
}
