///|
/// Run one operation while holding a mutex, releasing it on success or error.
async fn[X] with_mutex(mutex : @async.Mutex, operation : async () -> X) -> X {
  mutex.acquire()
  defer mutex.release()
  operation()
}

///|
/// A typed, single-socket RTNetlink client.
///
/// Every query is serialized by an async mutex, so only one task can write to
/// or read from the underlying socket at a time. The client owns the socket;
/// callers should invoke `close` when finished.
pub struct RouteClient {
  socket : RouteSocket
  requests : @async.Mutex
  request_timeout_ms : Int
  mut next_sequence : UInt
}

///|
/// Open a typed route client with no multicast subscriptions.
pub async fn RouteClient::open(
  receive_capacity? : Int = default_receive_capacity,
  request_timeout_ms? : Int = 5000,
) -> RouteClient {
  validate_request_timeout(request_timeout_ms)
  {
    socket: RouteSocket::open(receive_capacity~),
    requests: Mutex(),
    request_timeout_ms,
    next_sequence: 1,
  }
}

///|
fn RouteClient::take_sequence(self : RouteClient) -> UInt {
  let sequence = self.next_sequence
  self.next_sequence = advance_sequence(sequence)
  sequence
}

///|
fn advance_sequence(sequence : UInt) -> UInt {
  if sequence == 0xffffffff {
    1
  } else {
    sequence + 1
  }
}

///|
async fn RouteClient::request_dump_locked(
  self : RouteClient,
  build_request : (UInt) -> Bytes,
) -> Array[@core.NetlinkMessage] {
  let sequence = self.take_sequence()
  @async.with_timeout(
    self.request_timeout_ms,
    () => self.socket.request_dump(build_request(sequence), sequence),
    error=TransportError::RequestTimedOut(timeout_ms=self.request_timeout_ms),
  )
}

///|
async fn RouteClient::request_ack_locked(
  self : RouteClient,
  build_request : (UInt) -> Bytes raise?,
) -> Unit {
  let sequence = self.take_sequence()
  @async.with_timeout(
    self.request_timeout_ms,
    () => self.socket.request_ack(build_request(sequence), sequence),
    error=TransportError::RequestTimedOut(timeout_ms=self.request_timeout_ms),
  )
}

///|
fn find_link_name(links : ArrayView[@route.Link], index : Int) -> String? {
  for link in links {
    if link.index == index {
      return link.name
    }
  }
  None
}

///|
fn resolve_address_names(
  addresses : ArrayView[@route.Address],
  links : ArrayView[@route.Link],
) -> Array[@route.Address] {
  let result : Array[@route.Address] = []
  for address in addresses {
    result.push({
      family: address.family,
      interface_index: address.interface_index,
      interface_name: find_link_name(
        links,
        address.interface_index.reinterpret_as_int(),
      ),
      prefix_length: address.prefix_length,
      scope: address.scope,
      local_address: address.local_address,
      address: address.address,
      label: address.label,
      flags: address.flags,
      unknown_attributes: address.unknown_attributes,
    })
  }
  result
}

///|
fn resolve_neighbor_names(
  neighbors : ArrayView[@route.Neighbor],
  links : ArrayView[@route.Link],
) -> Array[@route.Neighbor] {
  let result : Array[@route.Neighbor] = []
  for neighbor in neighbors {
    result.push({
      family: neighbor.family,
      interface_index: neighbor.interface_index,
      interface_name: find_link_name(links, neighbor.interface_index),
      destination: neighbor.destination,
      link_layer_address: neighbor.link_layer_address,
      state: neighbor.state,
      flags: neighbor.flags,
      neighbor_type: neighbor.neighbor_type,
      probes: neighbor.probes,
      unknown_attributes: neighbor.unknown_attributes,
    })
  }
  result
}

///|
/// List all links through the client's serialized request path.
pub async fn RouteClient::get_links(self : RouteClient) -> Array[@route.Link] {
  with_mutex(self.requests, () => {
    let messages = self.request_dump_locked(@route.encode_get_links)
    @route.decode_links(messages)
  })
}

///|
/// Query one link by a positive interface index, under the request mutex and
/// timeout. A missing interface propagates the kernel errno.
pub async fn RouteClient::get_link_by_index(
  self : RouteClient,
  index : Int,
) -> @route.Link {
  with_mutex(self.requests, () => {
    let sequence = self.take_sequence()
    let request = @route.encode_get_link_by_index(sequence, index)
    let message = @async.with_timeout(
      self.request_timeout_ms,
      () => self.socket.request_single(request, sequence, @route.rtm_newlink),
      error=TransportError::RequestTimedOut(timeout_ms=self.request_timeout_ms),
    )
    @route.decode_link(message)
  })
}

///|
/// Query one link by a validated Linux interface name, under the request mutex
/// and timeout. A missing interface propagates the kernel errno.
pub async fn RouteClient::get_link_by_name(
  self : RouteClient,
  name : String,
) -> @route.Link {
  with_mutex(self.requests, () => {
    let sequence = self.take_sequence()
    let request = @route.encode_get_link_by_name(sequence, name)
    let message = @async.with_timeout(
      self.request_timeout_ms,
      () => self.socket.request_single(request, sequence, @route.rtm_newlink),
      error=TransportError::RequestTimedOut(timeout_ms=self.request_timeout_ms),
    )
    @route.decode_link(message)
  })
}

///|
/// Set one link administratively UP and wait for the kernel ACK.
pub async fn RouteClient::set_link_up(self : RouteClient, index : Int) -> Unit {
  with_mutex(self.requests, () => {
    self.request_ack_locked(fn(sequence) raise {
      @route.encode_set_link_state(sequence, index, true)
    })
  })
}

///|
/// Set one link administratively DOWN and wait for the kernel ACK.
pub async fn RouteClient::set_link_down(
  self : RouteClient,
  index : Int,
) -> Unit {
  with_mutex(self.requests, () => {
    self.request_ack_locked(fn(sequence) raise {
      @route.encode_set_link_state(sequence, index, false)
    })
  })
}

///|
/// List all addresses and resolve their interface names from a Link dump made
/// in the same serialized critical section.
pub async fn RouteClient::get_addresses(
  self : RouteClient,
) -> Array[@route.Address] {
  with_mutex(self.requests, () => {
    let link_messages = self.request_dump_locked(@route.encode_get_links)
    let links = @route.decode_links(link_messages)
    let address_messages = self.request_dump_locked(@route.encode_get_addresses)
    resolve_address_names(@route.decode_addresses(address_messages), links)
  })
}

///|
/// List all routes through the client's serialized request path.
pub async fn RouteClient::get_routes(self : RouteClient) -> Array[@route.Route] {
  with_mutex(self.requests, () => {
    let messages = self.request_dump_locked(@route.encode_get_routes)
    @route.decode_routes(messages)
  })
}

///|
/// List all neighbors and resolve their interface names from a Link dump made
/// in the same serialized critical section.
pub async fn RouteClient::get_neighbors(
  self : RouteClient,
) -> Array[@route.Neighbor] {
  with_mutex(self.requests, () => {
    let link_messages = self.request_dump_locked(@route.encode_get_links)
    let links = @route.decode_links(link_messages)
    let neighbor_messages = self.request_dump_locked(
      @route.encode_get_neighbors,
    )
    resolve_neighbor_names(@route.decode_neighbors(neighbor_messages), links)
  })
}

///|
/// Close the owned socket after any in-flight query completes. Repeated calls
/// are harmless because `RouteSocket::close` is idempotent.
pub async fn RouteClient::close(self : RouteClient) -> Unit {
  with_mutex(self.requests, () => self.socket.close())
}
