///|
test "typed NEW and DEL events preserve every domain object and unknown payload" {
  let address : @route.AddressSpec = {
    interface_index: 7,
    address: @route.IpAddress::parse("192.0.2.7"),
    prefix_length: 24,
    scope: 0,
  }
  let added = @core.decode_datagram(@route.encode_add_address(1, address))[0]
  guard @route.decode_event(added) is AddressAdded(value) else {
    fail("expected address event")
  }
  assert_eq(value.local_address, Some(address.address))
  guard @route.decode_event(
      @core.decode_datagram(@route.encode_delete_address(1, address))[0],
    )
    is AddressDeleted(_) else {
    fail("expected deletion event")
  }
  let link = @core.decode_datagram(@route.encode_set_link_mtu(1, 7, 1400))[0]
  guard @route.decode_event(link) is LinkChanged(value) else {
    fail("expected link event")
  }
  assert_eq(value.mtu, Some(1400))
  guard @route.decode_event({
      ..link,
      header: { ..link.header, message_type: 17, },
    })
    is LinkDeleted(_) else {
    fail("expected deletion event")
  }
  let route : @route.RouteSpec = {
    destination: @route.IpAddress::parse("192.0.2.0"),
    prefix_length: 24,
    gateway: None,
    output_interface: 7,
    table: 254,
    priority: None,
    protocol: 4,
    scope: 253,
  }
  let route_message = @core.decode_datagram(@route.encode_add_route(1, route))[0]
  assert_eq(
    @route.decode_event(route_message),
    RouteAdded(@route.decode_route(route_message)),
  )
  let deleted_route = @core.decode_datagram(
      @route.encode_delete_route(1, route),
    )[0]
  assert_eq(
    @route.decode_event(deleted_route),
    RouteDeleted(@route.decode_route(deleted_route)),
  )
  let neighbor_message = @core.decode_datagram(
      b"\x30\x00\x00\x00\x1c\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x07\x00\x00\x00\x80\x00\x00\x01\x08\x00\x01\x00\xc0\x00\x02\x01\x0a\x00\x02\x00\x02\x00\x00\x00\x00\x01\x00\x00",
    )[0]
  let neighbor = @route.decode_neighbor(neighbor_message)
  assert_eq(@route.decode_event(neighbor_message), NeighborChanged(neighbor))
  assert_eq(
    @route.decode_event({
      ..neighbor_message,
      header: { ..neighbor_message.header, message_type: 29, },
    }),
    NeighborDeleted(neighbor),
  )
  let unknown = { ..link, header: { ..link.header, message_type: 200, }, }
  assert_eq(@route.decode_event(unknown), Unknown(unknown))
}
