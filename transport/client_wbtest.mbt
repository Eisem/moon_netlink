///|
async test "request gate serializes concurrent operations" {
  let mutex : @async.Mutex = Mutex()
  let active = Ref::Ref(0)
  let maximum_active = Ref::Ref(0)
  let completed = Ref::Ref(0)
  @async.with_task_group(group => {
    let operation = () => {
      with_mutex(mutex, () => {
        active.val = active.val + 1
        if active.val > maximum_active.val {
          maximum_active.val = active.val
        }
        @async.pause()
        active.val = active.val - 1
        completed.val = completed.val + 1
      })
    }
    let first = group.spawn(operation)
    let second = group.spawn(operation)
    first.wait()
    second.wait()
  })
  assert_eq(maximum_active.val, 1)
  assert_eq(active.val, 0)
  assert_eq(completed.val, 2)
}

///|
async test "request mutex is released when an operation raises" {
  let mutex : @async.Mutex = Mutex()
  let operation : async () -> Unit = () => fail("expected test failure")
  try with_mutex(mutex, operation) catch {
    _ => ()
  } noraise {
    _ => fail("expected the operation to raise")
  }
  assert_true(mutex.try_acquire())
  mutex.release()
}

///|
test "sequence allocation skips zero when wrapping" {
  assert_eq(advance_sequence(0xffffffff), 1)
  assert_eq(advance_sequence(41), 42)
}

///|
#cfg(not(platform="windows"))
async test "live RouteClient serializes concurrent link dumps" {
  let client = RouteClient::open()
  defer client.socket.close()
  let (first, second) = @async.with_task_group(group => {
    let first = group.spawn(() => client.get_links())
    let second = group.spawn(() => client.get_links())
    (first.wait(), second.wait())
  })
  assert_true(first.length() > 0)
  assert_true(second.length() > 0)
  client.close()
}

///|
#cfg(not(platform="windows"))
async test "live Link point queries complete and share the serialized client" {
  let client = RouteClient::open(request_timeout_ms=1000)
  defer client.socket.close()
  let loopback = client.get_link_by_name("lo")
  let (by_index, by_name) = @async.with_task_group(group => {
    let by_index = group.spawn(() => client.get_link_by_index(loopback.index))
    let by_name = group.spawn(() => client.get_link_by_name("lo"))
    (by_index.wait(), by_name.wait())
  })
  assert_eq(by_index.index, loopback.index)
  assert_eq(by_index.name, Some("lo"))
  assert_eq(by_name.index, loopback.index)
  assert_true(client.get_links().length() > 0)
  client.close()
}

///|
#cfg(not(platform="windows"))
async test "live Link point-query errors release the request gate" {
  let client = RouteClient::open(request_timeout_ms=1000)
  defer client.socket.close()
  try client.get_link_by_index(0) catch {
    @route.LinkQueryError::InvalidInterfaceIndex(index~) => assert_eq(index, 0)
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("invalid index must fail")
  }
  try client.get_link_by_name("") catch {
    @route.LinkQueryError::EmptyInterfaceName => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("empty name must fail")
  }
  try client.get_link_by_name("mnl-none-261004") catch {
    KernelRejected(errno~) => assert_true(errno > 0)
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("missing interface must fail")
  }
  assert_eq(client.get_link_by_name("lo").name, Some("lo"))
  assert_true(client.get_links().length() > 0)
}
