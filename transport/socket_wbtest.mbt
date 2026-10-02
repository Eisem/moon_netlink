///|
test "receive capacity must fit a Netlink header" {
  try validate_receive_capacity(@core.nlmsg_header_length - 1) catch {
    InvalidReceiveCapacity(size~, minimum~) => {
      assert_eq(size, @core.nlmsg_header_length - 1)
      assert_eq(minimum, @core.nlmsg_header_length)
    }
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected a too-small receive capacity to fail")
  }
}

///|
test "short datagram is accepted" {
  validate_datagram_read(1024, 2048)
}

///|
test "full receive buffer fails closed" {
  try validate_datagram_read(2048, 2048) catch {
    DatagramMayBeTruncated(capacity~) => assert_eq(capacity, 2048)
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected a full datagram buffer to fail")
  }
}

///|
test "live truncation probe uses one valid Netlink datagram" {
  let request = @route.encode_get_links(9001)
  assert_eq(request.length(), 32)
  assert_eq(@core.read_u32_le(request, 0), 32)
}

///|
async test "transport whitebox async runtime is available" {
  @async.pause()
}

///|
/// Prove against a real Linux NETLINK_ROUTE socket that a deliberately tiny
/// receive buffer is rejected before the truncated response reaches codecs.
#cfg(not(platform="windows"))
async test "live Netlink datagram truncation fails closed" {
  @async.pause()
  let socket = RouteSocket::open(receive_capacity=@core.nlmsg_header_length)
  defer socket.close()
  let sequence : UInt = 9001
  try socket.request_dump(@route.encode_get_links(sequence), sequence) catch {
    DatagramMayBeTruncated(capacity~) =>
      assert_eq(capacity, @core.nlmsg_header_length)
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected the tiny receive buffer to reject the live dump")
  }
}
