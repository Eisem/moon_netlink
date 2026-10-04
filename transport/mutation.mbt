///|
/// Set MTU on an existing link and wait for its kernel ACK.
pub async fn RouteClient::set_link_mtu(
  self : RouteClient,
  index : Int,
  mtu : UInt,
) -> Unit {
  with_mutex(self.requests, () => {
    self.request_ack_locked(fn(sequence) raise {
      @route.encode_set_link_mtu(sequence, index, mtu)
    })
  })
}

///|
/// Add an address using exclusive creation by default.
pub async fn RouteClient::add_address(
  self : RouteClient,
  spec : @route.AddressSpec,
  mode? : @route.AddMode = Exclusive,
) -> Unit {
  with_mutex(self.requests, () => {
    self.request_ack_locked(fn(sequence) raise {
      @route.encode_add_address(sequence, spec, mode~)
    })
  })
}

///|
/// Delete a specified address and wait for its kernel ACK.
pub async fn RouteClient::delete_address(
  self : RouteClient,
  spec : @route.AddressSpec,
) -> Unit {
  with_mutex(self.requests, () => {
    self.request_ack_locked(fn(sequence) raise {
      @route.encode_delete_address(sequence, spec)
    })
  })
}

///|
/// Add a unicast route using exclusive creation by default.
pub async fn RouteClient::add_route(
  self : RouteClient,
  spec : @route.RouteSpec,
  mode? : @route.AddMode = Exclusive,
) -> Unit {
  with_mutex(self.requests, () => {
    self.request_ack_locked(fn(sequence) raise {
      @route.encode_add_route(sequence, spec, mode~)
    })
  })
}

///|
/// Delete a specified unicast route and wait for its kernel ACK.
pub async fn RouteClient::delete_route(
  self : RouteClient,
  spec : @route.RouteSpec,
) -> Unit {
  with_mutex(self.requests, () => {
    self.request_ack_locked(fn(sequence) raise {
      @route.encode_delete_route(sequence, spec)
    })
  })
}
