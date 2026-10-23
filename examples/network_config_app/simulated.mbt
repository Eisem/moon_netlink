///|
/// Simulated failure scenarios for the application sample.
///
/// The backend observes the real kernel through the caller's `RouteClient` but
/// answers every mutation from a fixed scenario, so an application can exercise
/// its own failure handling without writing to the network. `SimulatedBackend`
/// is an ordinary implementation of the public `NetworkBackend` trait; no
/// library internals are involved.

///|
/// Reported when the application cannot accept the outcome of a run.
suberror ApplicationNotConverged derive(Debug)

///|
/// Reported when a simulated operation does not return a determinate result, so
/// `reconcile` must mark the failure's outcome as unknown.
suberror SimulatedTimeout derive(Debug)

///|
/// Which simulated behaviour the backend implements.
enum SimMode {
  Partial
  Unknown
  Compensation
  TargetUnmet
} derive(Debug, Eq)

///|
fn SimMode::name(self : SimMode) -> String {
  match self {
    Partial => "partial"
    Unknown => "unknown"
    Compensation => "compensation"
    TargetUnmet => "target-unmet"
  }
}

///|
/// Number of mutations attempted before the scenario reacts. The third mutation
/// is the first address addition of the sample configuration.
let simulated_failure_call : Int32 = 3

///|
struct SimulatedBackend {
  client : @transport.RouteClient
  mode : SimMode
  calls : Array[Int32]
}

///|
fn SimulatedBackend::new(
  client : @transport.RouteClient,
  mode : SimMode,
) -> SimulatedBackend {
  { client, mode, calls: [0], }
}

///|
impl @reconcile.NetworkBackend for SimulatedBackend with fn snapshot(self) {
  @state.NetworkSnapshot::new(
    links=self.client.get_links(),
    addresses=self.client.get_addresses(),
    routes=self.client.get_routes(),
    neighbors=self.client.get_neighbors(),
  )
}

///|
impl @reconcile.NetworkBackend for SimulatedBackend with fn execute(
  self,
  change,
) {
  ignore(change)
  self.calls[0] = self.calls[0] + 1
  let call = self.calls[0]
  match self.mode {
    Partial =>
      if call == simulated_failure_call {
        raise @transport.TransportError::KernelRejected(errno=101)
      }
    Unknown => if call == simulated_failure_call { raise SimulatedTimeout }
    Compensation =>
      if call >= simulated_failure_call {
        // The failure and every later compensation fail, so the report must
        // show that recovery did not succeed.
        raise @transport.TransportError::KernelRejected(errno=101)
      }
    TargetUnmet => ()
  }
}
