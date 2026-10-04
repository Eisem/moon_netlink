///|
test "route JSON order is invariant under permutations of distinct output fields" {
  let base : @route.Route = {
    family: Ipv6,
    destination: Some(@route.IpAddress::parse("2001:db8:ffff::")),
    destination_prefix_length: 64,
    source: Some(@route.IpAddress::parse("2001:db8::")),
    source_prefix_length: 64,
    gateway: None,
    preferred_source: None,
    input_interface: None,
    output_interface: Some(1),
    table: 254,
    priority: Some(1024),
    protocol: 3,
    scope: 0,
    route_type: 1,
    tos: 0,
    flags: 0,
    unknown_attributes: [],
  }
  let variants : Array[@route.Route] = [
    { ..base, family: Ipv4, },
    { ..base, table: 1000, },
    { ..base, destination: None, },
    { ..base, destination_prefix_length: 96, },
    { ..base, source: None, },
    { ..base, source_prefix_length: 96, },
    { ..base, preferred_source: Some(@route.IpAddress::parse("2001:db8::1")), },
    { ..base, gateway: Some(@route.IpAddress::parse("fe80::1")), },
    { ..base, input_interface: Some(2), },
    { ..base, output_interface: None, },
    { ..base, priority: None, },
    { ..base, protocol: 4, },
    { ..base, scope: 253, },
    { ..base, route_type: 2, },
    { ..base, tos: 1, },
    { ..base, flags: 1, },
  ]
  for variant in variants {
    assert_eq(
      format_routes([base, variant], true),
      format_routes([variant, base], true),
    )
    assert_eq(
      format_routes([base, variant], false),
      format_routes([variant, base], false),
    )
  }
  let forward = variants.copy()
  let reverse = variants.rev()
  assert_eq(format_routes(forward, true), format_routes(reverse, true))
}
