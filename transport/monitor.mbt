///|
/// Legacy RTNetlink multicast group mask for Link, IPv4/IPv6 Address/Route,
/// and Neighbor changes (RTMGRP_LINK/NEIGH/IPV4_IFADDR/IPV4_ROUTE/IPv6 variants).
pub let route_monitor_groups : UInt = 0x0555

///|
/// An independent multicast socket. No client request uses this descriptor.
pub struct RouteMonitor {
  socket : RouteSocket
  readers : @async.Mutex
  buffer : FixedArray[Byte]
  pending : Array[@route.RouteEvent]
  mut next : Int
  mut read_task : @async.Task[Int]?
}

///|
/// Subscribe before producing changes. Errors indicating data loss require a
/// new query/snapshot; this stream does not silently hide dropped events.
pub async fn RouteMonitor::open(
  groups? : UInt = route_monitor_groups,
  receive_capacity? : Int = default_receive_capacity,
) -> RouteMonitor {
  {
    socket: RouteSocket::open(groups~, receive_capacity~),
    readers: Mutex(),
    buffer: FixedArray::make(receive_capacity, b'\x00'),
    pending: [],
    next: 0,
    read_task: None,
  }
}

///|
/// Read the next typed event, serializing concurrent readers. Interface names
/// on Address/Neighbor remain unresolved to avoid extra event-stream queries.
pub async fn RouteMonitor::next_event(self : RouteMonitor) -> @route.RouteEvent {
  with_mutex(self.readers, () => {
    for ;; {
      if self.socket.closed {
        raise TransportError::ReadClosed
      }
      if self.next < self.pending.length() {
        let event = self.pending[self.next]
        self.next = self.next + 1
        return event
      }
      self.pending.clear()
      self.next = 0
      let count = @async.with_task_group(group => {
        let reader = group.spawn(
          () => self.socket.source.read(self.buffer),
          allow_failure=true,
        )
        self.read_task = Some(reader)
        defer {
          self.read_task = None
        }
        reader.wait()
      }) catch {
        @os_error.OSError(105, ..) => raise TransportError::EventStreamLost
        err => {
          if self.socket.closed {
            raise TransportError::ReadClosed
          }
          raise err
        }
      }
      if count == 0 {
        raise TransportError::ReadClosed
      }
      validate_datagram_read(count, self.buffer.length())
      let messages = @core.decode_datagram(
        Bytes::from_array(self.buffer[:count]),
      )
      let events = decode_event_datagram(messages)
      for event in events {
        self.pending.push(event)
      }
    }
  })
}

///|
// Validate the complete datagram before enqueueing any event. An error in a
// later message must not leave earlier events queued for a subsequent call.
fn decode_event_datagram(
  messages : ArrayView[@core.NetlinkMessage],
) -> Array[@route.RouteEvent] raise {
  let events = []
  for message in messages {
    match @core.decode_control(message) {
      Some(Noop) | Some(Ack(_)) => ()
      Some(Overrun) => raise TransportError::EventStreamLost
      Some(KernelError(errno, _)) => reject_kernel_message(message, errno)
      Some(Done(_)) =>
        raise TransportError::UnexpectedControl(
          message_type=message.header.message_type,
        )
      None => events.push(@route.decode_event(message))
    }
  }
  events
}

///|
/// Close the monitor, waking a pending RawFd read. Repeated calls are harmless.
pub fn RouteMonitor::close(self : RouteMonitor) -> Unit {
  if self.read_task is Some(reader) {
    reader.cancel()
  }
  self.socket.close()
  self.pending.clear()
}
