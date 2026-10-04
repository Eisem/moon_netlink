///|
async test "failure compensates only completed steps in reverse order" {
  let (network, plan) = network_fixture(Some(2))
  let report = @reconcile.apply_plan(network, plan, dry_run=false)
  assert_eq(report.completed, [0, 1])
  assert_eq(report.rollback.map(item => item.index), [1, 0])
  assert_true(network.calls[3] is SetLinkUp(after=false, ..))
  assert_true(network.calls[4] is SetMtu(after=1500, ..))
  assert_true(report.rollback.all(item => item.status is Completed))
  assert_true(report.failed is Some({ index: 2, .. }))
}

///|
struct FailingRollback {
  network : FakeNetwork
}

///|
impl @reconcile.NetworkBackend for FailingRollback with fn snapshot(self) {
  self.network.observation
}

///|
impl @reconcile.NetworkBackend for FailingRollback with fn execute(self, change) {
  self.network.calls.push(change)
  if self.network.calls.length() == 3 || self.network.calls.length() == 4 {
    raise @transport.TransportError::KernelRejected(
      errno=if self.network.calls.length() == 3 { 101 } else { 1 },
    )
  }
}

///|
async test "rollback failure does not replace original cause or stop later compensations" {
  let (network, plan) = network_fixture(None)
  let backend : FailingRollback = { network, }
  let report = @reconcile.apply_plan(backend, plan, dry_run=false)
  guard report.failed is Some(failure) else { fail("missing execution error") }
  assert_true(
    failure.error is @transport.TransportError::KernelRejected(errno=101),
  )
  assert_true(
    report.rollback[0].status
    is Failed(@transport.TransportError::KernelRejected(errno=1)),
  )
  assert_true(report.rollback[1].status is Completed)
  assert_eq(network.calls.length(), 5)
}

///|
async test "unobserved MTU is explicitly unavailable for compensation" {
  let (network, plan) = network_fixture(Some(1))
  plan.steps[0] = {
    ..plan.steps[0],
    change: SetMtu(name="veth0", index=7, before=None, after=1400),
  }
  let report = @reconcile.apply_plan(network, plan, dry_run=false)
  assert_true(report.rollback[0].status is Unavailable(_))
  assert_true(report.rollback[0].change is None)
  assert_eq(network.calls.length(), 2)
}
