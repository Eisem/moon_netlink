///|
#warnings("-implicit_impl_as_method")
pub(all) suberror TransportError {
  UnsupportedPlatform
  OpenFailed(errno~ : Int)
  InvalidReceiveCapacity(size~ : Int, minimum~ : Int)
  ReadClosed
  DatagramMayBeTruncated(capacity~ : Int)
  ShortWrite(expected~ : Int, actual~ : Int)
  KernelRejected(errno~ : Int)
  UnexpectedControl(message_type~ : UInt16)
} derive(Debug, Eq)

///|
pub extend TransportError with Debug::{to_repr}

///|
pub extend TransportError with Eq::{equal, not_equal}

///|
/// An independently owned, connected NETLINK_ROUTE socket.
pub struct RouteSocket {
  source : @raw_fd.RawFd
  receive_capacity : Int
  mut closed : Bool
}

///|
let default_receive_capacity : Int = 256 * 1024

///|
fn validate_receive_capacity(size : Int) -> Unit raise TransportError {
  if size < @core.nlmsg_header_length {
    raise InvalidReceiveCapacity(size~, minimum=@core.nlmsg_header_length)
  }
}

///|
fn validate_datagram_read(
  count : Int,
  capacity : Int,
) -> Unit raise TransportError {
  // RawFd exposes read(2), not recvmsg(2) with MSG_TRUNC. For a datagram
  // socket, filling the entire user buffer is therefore ambiguous: it may be
  // an exact-size packet or a truncated larger one. Failing closed prevents a
  // truncated Netlink dump from being accepted as complete.
  if count >= capacity {
    raise DatagramMayBeTruncated(capacity~)
  }
}

///|
/// Open a nonblocking NETLINK_ROUTE socket and register it with async I/O.
///
/// `receive_capacity` bounds one kernel datagram, not an entire multipart
/// dump. A read that fills this buffer is rejected because RawFd cannot expose
/// Linux's MSG_TRUNC flag. The default is 256 KiB.
pub async fn RouteSocket::open(
  groups? : UInt = 0,
  receive_capacity? : Int = default_receive_capacity,
) -> RouteSocket {
  validate_receive_capacity(receive_capacity)
  let native = native_open_route_socket(groups)
  let errno = native.open_error()
  if errno != 0 {
    if errno == 38 {
      raise TransportError::UnsupportedPlatform
    }
    raise TransportError::OpenFailed(errno~)
  }
  let descriptor = native.take_fd()
  let source = @raw_fd.RawFd(descriptor) catch {
    @os_error.OSError(errno, ..) => raise TransportError::OpenFailed(errno~)
    err => raise err
  }
  { source, receive_capacity, closed: false, }
}

///|
/// Close the descriptor. Calling close more than once is harmless.
pub fn RouteSocket::close(self : RouteSocket) -> Unit {
  if !self.closed {
    self.closed = true
    self.source.close()
  }
}

///|
/// Send one request and collect its multipart response through NLMSG_DONE.
///
/// This feasibility implementation serializes at the caller. It fails closed
/// when a datagram fills the configured receive buffer, because the excess
/// bytes would already have been discarded by the kernel.
pub async fn RouteSocket::request_dump(
  self : RouteSocket,
  request : Bytes,
  sequence : UInt,
) -> Array[@core.NetlinkMessage] {
  if self.closed {
    raise TransportError::ReadClosed
  }
  let written = self.source.write(request)
  if written != request.length() {
    raise TransportError::ShortWrite(expected=request.length(), actual=written)
  }
  let result : Array[@core.NetlinkMessage] = []
  let buffer = FixedArray::make(self.receive_capacity, b'\x00')
  for ;; {
    let count = self.source.read(buffer)
    if count == 0 {
      raise TransportError::ReadClosed
    }
    validate_datagram_read(count, self.receive_capacity)
    let datagram = Bytes::from_array(buffer[:count])
    let messages = @core.decode_datagram(datagram)
    for message in messages {
      if message.header.sequence != sequence {
        continue
      }
      let message_type = message.header.message_type
      if message_type == @core.nlmsg_done {
        return result
      } else if message_type == @core.nlmsg_error {
        let errno = @core.read_i32_le(message.payload, 0)
        if errno == 0 {
          return result
        }
        raise TransportError::KernelRejected(errno=-errno)
      } else if message_type == @core.nlmsg_noop {
        ()
      } else if message_type == @core.nlmsg_overrun {
        raise TransportError::UnexpectedControl(message_type~)
      } else {
        result.push(message)
      }
    }
  }
}
