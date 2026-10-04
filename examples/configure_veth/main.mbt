///|
/// Run only on a disposable interface inside a temporary network namespace.
async fn main {
  let args = @env.args()
  guard args.length() == 4 && args[3] == "--yes" else {
    fail(
      "Usage (isolated namespace only): configure_veth <ifname> <add|delete> --yes",
    )
  }
  guard args[2] == "add" || args[2] == "delete" else {
    fail("expected add or delete")
  }
  @async.with_task_group(group => {
    let client = @transport.RouteClient::open()
    group.add_defer(() => @async.protect_from_cancel(() => client.close()))
    let link = client.get_link_by_name(args[1])
    let ipv4 : @route.AddressSpec = {
      interface_index: link.index,
      address: @route.IpAddress::parse("192.0.2.10"),
      prefix_length: 24,
      scope: 0,
    }
    let ipv6 : @route.AddressSpec = {
      ..ipv4,
      address: @route.IpAddress::parse("2001:db8::10"),
      prefix_length: 64,
    }
    let route4 : @route.RouteSpec = {
      destination: @route.IpAddress::parse("198.51.100.0"),
      prefix_length: 24,
      gateway: Some(@route.IpAddress::parse("192.0.2.1")),
      output_interface: link.index,
      table: 1000,
      priority: Some(42),
      protocol: 4,
      scope: 0,
    }
    let route6 : @route.RouteSpec = {
      ..route4,
      destination: @route.IpAddress::parse("2001:db8:1::"),
      prefix_length: 64,
      gateway: None,
    }
    if args[2] == "delete" {
      client.delete_route({
        ..route4,
        gateway: Some(@route.IpAddress::parse("192.0.2.2")),
      })
      client.delete_route(route6)
      client.delete_address(ipv4)
      client.delete_address(ipv6)
      client.set_link_down(link.index)
      client.set_link_mtu(link.index, 1500)
      assert_false(
        client
        .get_addresses()
        .any(address => {
          address.local_address == Some(ipv4.address) ||
          address.address == Some(ipv6.address)
        }),
      )
      assert_false(client.get_routes().any(route => route.table == 1000))
      println("isolated IPv4/IPv6 route/address deletion and Link DOWN: ok")
      return
    }
    client.set_link_mtu(link.index, 1400)
    client.set_link_up(link.index)
    client.add_address(ipv4)
    client.add_address(ipv6)
    // Exclusive creation must fail on duplicates and leave the socket reusable.
    try client.add_address(ipv4) catch {
      @transport.TransportError::KernelRejected(errno~)
      | @transport.TransportError::KernelRejectedDetailed(errno~, ..) =>
        assert_eq(errno, 17)
      err => fail("unexpected duplicate-address error: \{Repr(err)}")
    } noraise {
      _ => fail("duplicate exclusive address accepted")
    }
    client.add_address(ipv4, mode=Replace)
    client.add_route(route4)
    client.add_route(route6)
    try client.add_route(route4) catch {
      @transport.TransportError::KernelRejected(errno~)
      | @transport.TransportError::KernelRejectedDetailed(errno~, ..) =>
        assert_eq(errno, 17)
      err => fail("unexpected duplicate-route error: \{Repr(err)}")
    } noraise {
      _ => fail("duplicate exclusive route accepted")
    }
    let replacement = {
      ..route4,
      gateway: Some(@route.IpAddress::parse("192.0.2.2")),
    }
    client.add_route(replacement, mode=Replace)
    let routes = client.get_routes()
    assert_true(
      routes.any(route => {
        route.table == 1000 && route.gateway == replacement.gateway
      }),
    )
    assert_false(
      routes.any(route => route.table == 1000 && route.gateway == route4.gateway),
    )
    assert_eq(client.get_link_by_index(link.index).mtu, Some(1400))
    let addresses = client.get_addresses()
    assert_true(
      addresses.any(address => address.local_address == Some(ipv4.address)),
    )
    assert_true(addresses.any(address => address.address == Some(ipv6.address)))
    // A gateway outside the connected subnet exercises kernel extack text.
    try
      client.add_route({
        ..route4,
        gateway: Some(@route.IpAddress::parse("192.0.3.1")),
      })
    catch {
      @transport.TransportError::KernelRejectedDetailed(
        errno~,
        extack~,
        original_header~
      ) => {
        assert_true(errno > 0)
        assert_true(extack.message is Some(_))
        assert_true(original_header is Some(_))
        println("kernel errno \{errno}: \{extack.message.unwrap()}")
      }
      err => fail("expected a structured kernel extack: \{Repr(err)}")
    } noraise {
      _ => fail("invalid gateway accepted")
    }
    assert_true(client.get_links().length() > 0)
    println(
      "isolated MTU, IPv4/IPv6 address/route, exclusive/replace and extack: ok",
    )
  })
}
