///|
test "monitor preserves batched events and fails on overrun or malformed data" {
  let first = response_message(100)
  let second = response_message(101)
  assert_eq(
    decode_event_datagram([first, response_message(@core.nlmsg_noop), second]),
    [Unknown(first), Unknown(second)],
  )
  try
    decode_event_datagram([first, response_message(@core.nlmsg_overrun)])
  catch {
    EventStreamLost => ()
    err => fail("unexpected overrun error: \{Repr(err)}")
  } noraise {
    _ => fail("overrun must report event loss")
  }
  try
    decode_event_datagram([first, response_message(@route.rtm_newaddr)])
  catch {
    @core.CodecError::Truncated(..) => ()
    err => fail("unexpected malformed event error: \{Repr(err)}")
  } noraise {
    _ => fail("malformed event accepted")
  }
}

///|
#cfg(not(platform="windows"))
async test "live monitor cancellation leaves the independent socket reusable" {
  let monitor = RouteMonitor::open(groups=0)
  defer monitor.close()
  for _ in 0..<2 {
    try
      @async.with_timeout(
        10,
        () => monitor.next_event(),
        error=TransportError::RequestTimedOut(timeout_ms=10),
      )
    catch {
      RequestTimedOut(..) => ()
      err => fail("unexpected monitor error: \{Repr(err)}")
    } noraise {
      _ => fail("an unsubscribed monitor must wait")
    }
  }
  let client = RouteClient::open()
  defer client.socket.close()
  assert_true(client.get_links().length() > 0)
  monitor.close()
  monitor.close()
  try monitor.next_event() catch {
    ReadClosed => ()
    err => fail("unexpected closed monitor error: \{Repr(err)}")
  } noraise {
    _ => fail("closed monitor read succeeded")
  }
}

///|
#cfg(not(platform="windows"))
async test "live monitor close wakes a pending reader" {
  let monitor = RouteMonitor::open(groups=0)
  defer monitor.close()
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let reader = group.spawn(() => {
        try monitor.next_event() catch {
          ReadClosed => ()
          err => fail("unexpected close error: \{Repr(err)}")
        } noraise {
          _ => fail("closed monitor returned an event")
        }
      })
      @async.pause()
      monitor.close()
      reader.wait()
    })
  })
}
