///|
struct ObservedNetwork {
  mut observation : @state.NetworkSnapshot
  ignore_writes : Bool
  fail_final : Bool
  mut snapshots : Int
}

///|
impl @reconcile.NetworkBackend for ObservedNetwork with fn snapshot(self) {
  self.snapshots += 1
  if self.fail_final && self.snapshots >= 3 {
    raise @transport.TransportError::ReadClosed
  }
  self.observation
}

///|
impl @reconcile.NetworkBackend for ObservedNetwork with fn execute(self, change) {
  if self.ignore_writes {
    return
  }
  let link = self.observation.links[0]
  let updated = match change {
    SetMtu(after~, ..) => { ..link, mtu: Some(after), }
    SetLinkUp(after~, ..) =>
      {
        ..link,
        flags: if after {
          link.flags | 1
        } else {
          link.flags & 0xfffffffe
        },
      }
    _ => fail("fixture supports link changes only")
  }
  self.observation = @state.NetworkSnapshot::new(
    links=[updated],
    addresses=[],
    routes=[],
    neighbors=[],
  )
}

///|
async test "final verification detects ineffective ACK and exposes unmet plan" {
  let (fixture, _) = network_fixture(None)
  let desired = @state.DesiredState::parse(
    "{\"schema_version\":1,\"links\":[{\"name\":\"veth0\",\"ensure\":\"present\",\"mtu\":1400,\"up\":true}]}",
  )
  let network : ObservedNetwork = {
    observation: fixture.observation,
    ignore_writes: true,
    fail_final: false,
    snapshots: 0,
  }
  let report = @reconcile.reconcile(network, desired, dry_run=false)
  assert_true(report.completed_without_error())
  assert_false(report.succeeded())
  assert_eq(report.verification.unwrap().remaining.unwrap().steps.length(), 2)
  assert_true(
    report.to_json() is { "verification": { "satisfied": False, .. }, .. },
  )
}

///|
async test "observed goals succeed and repeated reconcile generates no operations" {
  let (fixture, _) = network_fixture(None)
  let desired = @state.DesiredState::parse(
    "{\"schema_version\":1,\"links\":[{\"name\":\"veth0\",\"ensure\":\"present\",\"mtu\":1400,\"up\":true}]}",
  )
  let network : ObservedNetwork = {
    observation: fixture.observation,
    ignore_writes: false,
    fail_final: false,
    snapshots: 0,
  }
  assert_true(@reconcile.reconcile(network, desired, dry_run=false).succeeded())
  let again = @reconcile.reconcile(network, desired, dry_run=false)
  assert_true(again.succeeded())
  assert_eq(again.plan.steps.length(), 0)
}

///|
async test "final read errors cannot turn acknowledged execution into success" {
  let (fixture, _) = network_fixture(None)
  let desired = @state.DesiredState::parse(
    "{\"schema_version\":1,\"links\":[{\"name\":\"veth0\",\"ensure\":\"present\",\"mtu\":1400}]}",
  )
  let network : ObservedNetwork = {
    observation: fixture.observation,
    ignore_writes: false,
    fail_final: true,
    snapshots: 0,
  }
  let report = @reconcile.reconcile(network, desired, dry_run=false)
  assert_true(report.completed_without_error())
  assert_false(report.succeeded())
  assert_true(
    report.verification.unwrap().error
    is Some(@transport.TransportError::ReadClosed),
  )
}
