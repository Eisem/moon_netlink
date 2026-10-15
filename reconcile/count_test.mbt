///|
/// Counts explicit simulated sends independently of acknowledged completions.
struct MeasuredNetwork {
  observation : @state.NetworkSnapshot
  sent : Array[@state.Change]
  reject_before_send : Bool
}

///|
impl @reconcile.NetworkBackend for MeasuredNetwork with fn snapshot(self) {
  self.observation
}

///|
impl @reconcile.NetworkBackend for MeasuredNetwork with fn mutation_attempts(
  self,
) {
  Some(self.sent.length())
}

///|
impl @reconcile.NetworkBackend for MeasuredNetwork with fn execute(self, change) {
  if self.reject_before_send {
    raise @state.SafetyError::StaleInterface(
      interface="veth0",
      planned_index=7,
      observed_index=Some(8),
    )
  }
  self.sent.push(change)
  if self.sent.length() == 2 {
    raise @transport.TransportError::KernelRejected(errno=22)
  }
}

///|
async test "measured forward and compensation sends are separate" {
  let (fixture, plan) = network_fixture(None)
  let backend : MeasuredNetwork = {
    observation: fixture.observation,
    sent: [],
    reject_before_send: false,
  }
  let report = @reconcile.apply_plan(backend, plan, dry_run=false)
  assert_eq(report.attempted_writes, Some(2))
  assert_eq(report.compensations, Some(1))
  assert_eq(report.completed, [0])
  assert_eq(backend.sent.length(), 3)
}

///|
async test "failure before send is not counted as a write" {
  let (fixture, plan) = network_fixture(None)
  let backend : MeasuredNetwork = {
    observation: fixture.observation,
    sent: [],
    reject_before_send: true,
  }
  let report = @reconcile.apply_plan(backend, plan, dry_run=false)
  assert_true(report.failed is Some(_))
  assert_eq(report.attempted_writes, Some(0))
  assert_eq(report.compensations, Some(0))
}

///|
async test "measured dry run reports zero sends" {
  let (fixture, plan) = network_fixture(None)
  let backend : MeasuredNetwork = {
    observation: fixture.observation,
    sent: [],
    reject_before_send: false,
  }
  let report = @reconcile.apply_plan(backend, plan)
  assert_eq(report.attempted_writes, Some(0))
  assert_eq(report.compensations, Some(0))
}

///|
async test "unmeasured backend does not invent write counts" {
  let (backend, plan) = network_fixture(None)
  let report = @reconcile.apply_plan(backend, plan, dry_run=false)
  assert_eq(report.attempted_writes, None)
  assert_eq(report.compensations, None)
}
