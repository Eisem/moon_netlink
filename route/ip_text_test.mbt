///|
test "strict IPv4 parsing and formatting" {
  assert_eq(@route.Ipv4Address::parse("192.0.2.10").to_string(), "192.0.2.10")
  assert_eq(@route.IpAddress::parse("0.0.0.0").to_string(), "0.0.0.0")
  for invalid in ["", "127.1", "256.0.0.1", "01.2.3.4", "1.2.3.4.5"] {
    try @route.Ipv4Address::parse(invalid) catch {
      InvalidIpv4(input~) => assert_eq(input, invalid)
      err => fail("unexpected error: \{Repr(err)}")
    } noraise {
      _ => fail("expected invalid IPv4: \{invalid}")
    }
  }
}

///|
test "strict IPv6 parsing and RFC 5952 formatting" {
  let cases = [
    ("::", "::"),
    ("::1", "::1"),
    ("2001:0db8:0000:0000:0000:ff00:0042:8329", "2001:db8::ff00:42:8329"),
    ("2001:db8:0:1:0:0:0:1", "2001:db8:0:1::1"),
    ("::ffff:192.0.2.128", "::ffff:c000:280"),
    ("0:0:0:0:0:ffff:192.0.2.128", "::ffff:c000:280"),
  ]
  for (input, expected) in cases {
    assert_eq(@route.Ipv6Address::parse(input).to_string(), expected)
    assert_eq(@route.IpAddress::parse(input).to_string(), expected)
  }
  for
    invalid in [
      "", ":", ":::1", "1::2::3", "1:2:3:4:5:6:7", "1:2:3:4:5:6:7:8::", "gggg::1",
      "::ffff:192.168.001.1",
    ] {
    try @route.Ipv6Address::parse(invalid) catch {
      InvalidIpv6(input~) => assert_eq(input, invalid)
      err => fail("unexpected error: \{Repr(err)}")
    } noraise {
      _ => fail("expected invalid IPv6: \{invalid}")
    }
  }
}

///|
test "strict MAC parsing and canonical formatting" {
  assert_eq(
    @route.MacAddress::parse("02:42:AC:11:00:02").to_string(),
    "02:42:ac:11:00:02",
  )
  for
    invalid in [
      "", "02:42:ac:11:00", "2:42:ac:11:00:02", "02-42-ac-11-00-02", "02:42:ac:11:00:gg",
    ] {
    try @route.MacAddress::parse(invalid) catch {
      InvalidMac(input~) => assert_eq(input, invalid)
      err => fail("unexpected error: \{Repr(err)}")
    } noraise {
      _ => fail("expected invalid MAC: \{invalid}")
    }
  }
}
