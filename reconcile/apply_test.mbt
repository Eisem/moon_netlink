///|
struct FakeNetwork {
  observation : @state.NetworkSnapshot
  calls : Array[@state.Change]
  fail_at : Int?
  failure : Error
  delay_ms : Int
  edit_plan : @state.Plan?
}

///|
impl @reconcile.NetworkBackend for FakeNetwork with fn snapshot(self) {
  if self.edit_plan is Some(plan) {
    plan.steps.clear()
  }
  self.observation
}

///|
impl @reconcile.NetworkBackend for FakeNetwork with fn execute(self, change) {
  self.calls.push(change)
  if self.delay_ms > 0 {
    @async.sleep(self.delay_ms)
  }
  if self.fail_at == Some(self.calls.length() - 1) {
    raise self.failure
  }
}

///|
fn network_fixture(fail_at : Int?) -> (FakeNetwork, @state.Plan) raise {
  let link : @route.Link = {
    index: 7,
    name: Some("veth0"),
    kind: None,
    mtu: Some(1500),
    mac: None,
    flags: 0,
    operational_state: None,
    master_index: None,
    unknown_attributes: [],
  }
  let observation = @state.NetworkSnapshot::new(
    links=[link],
    addresses=[],
    routes=[],
    neighbors=[],
  )
  let plan = @state.build_plan(
    observation,
    @state.DesiredState::parse(
      "{\"schema_version\":1,\"links\":[{\"name\":\"veth0\",\"ensure\":\"present\",\"up\":true,\"mtu\":1400}],\"addresses\":[{\"interface\":\"veth0\",\"ensure\":\"present\",\"address\":\"192.0.2.1\",\"prefix_length\":24}]}",
    ),
  )
  (
    {
      observation,
      calls: [],
      fail_at,
      failure: @transport.TransportError::KernelRejected(errno=22),
      delay_ms: 0,
      edit_plan: None,
    },
    plan,
  )
}

///|
async test "preflight rejects protected resources before the first write" {
  let (network, plan) = network_fixture(None)
  let link = network.observation.links[0]
  let guarded = {
    ..network,
    observation: @state.NetworkSnapshot::new(
      links=[{ ..link, flags: 8, }],
      addresses=[],
      routes=[],
      neighbors=[],
    ),
  }
  try @reconcile.apply_plan(guarded, plan, dry_run=false) catch {
    @state.SafetyError::ProtectedResource(..) => ()
    err => fail("unexpected safety error: \{Repr(err)}")
  } noraise {
    _ => fail("protected execution accepted")
  }
  assert_eq(guarded.calls.length(), 0)
}

///|
async test "execution owns plan before a backend can mutate caller arrays" {
  let (network, plan) = network_fixture(None)
  let editing = { ..network, edit_plan: Some(plan), }
  let report = @reconcile.apply_plan(editing, plan, dry_run=false)
  assert_eq(plan.steps.length(), 0)
  assert_eq(report.plan.steps.length(), 3)
  assert_eq(report.completed, [0, 1, 2])
}

///|
async test "cancellation accounts for in-flight ACK and stops remaining operations" {
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let (network, plan) = network_fixture(None)
      let delayed = { ..network, delay_ms: 20, }
      let task = group.spawn(() => {
        @reconcile.apply_plan(delayed, plan, dry_run=false)
      })
      while delayed.calls.is_empty() {
        @async.pause()
      }
      task.cancel()
      let report = task.wait()
      assert_true(report.cancelled)
      assert_eq(report.completed, [0])
      assert_eq(report.not_executed, [1, 2])
      assert_eq(delayed.calls.length(), 2)
      assert_false(report.completed_without_error())
    })
  })
}

///|
async test "default dry-run never calls backend mutations" {
  let (network, plan) = network_fixture(None)
  let report = @reconcile.apply_plan(network, plan)
  assert_true(report.dry_run)
  assert_eq(network.calls.length(), 0)
  assert_eq(report.not_executed, [0, 1, 2])
  assert_false(report.completed_without_error())
}

///|
async test "executor orders operations and stops with typed partial failure" {
  let (network, plan) = network_fixture(Some(1))
  let report = @reconcile.apply_plan(network, plan, dry_run=false)
  assert_eq(report.completed, [0])
  assert_eq(report.not_executed, [2])
  assert_eq(network.calls.length(), 3)
  assert_true(network.calls[0] is SetMtu(..))
  assert_true(network.calls[1] is SetLinkUp(..))
  guard report.failed is Some(failure) else { fail("missing failure") }
  assert_false(failure.outcome_unknown)
  assert_true(
    failure.error is @transport.TransportError::KernelRejected(errno=22),
  )
  assert_true(
    report.to_json()
    is { "failed": { "error": { "errno": Number(22, ..), .. }, .. }, .. },
  )
  let (healthy, plan) = network_fixture(None)
  assert_true(
    @reconcile.apply_plan(healthy, plan, dry_run=false).completed_without_error(),
  )
}

///|
async test "timeout preserves typed cause and reports uncertain mutation outcome" {
  let (network, plan) = network_fixture(Some(0))
  let timed = {
    ..network,
    failure: @transport.TransportError::RequestTimedOut(timeout_ms=10),
  }
  let report = @reconcile.apply_plan(timed, plan, dry_run=false)
  guard report.failed is Some(failure) else { fail("missing failure") }
  assert_true(failure.outcome_unknown)
  assert_true(
    failure.error is @transport.TransportError::RequestTimedOut(timeout_ms=10),
  )
  assert_eq(report.completed, [])
  assert_eq(report.not_executed, [1, 2])
}
