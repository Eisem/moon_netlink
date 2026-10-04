///|
/// An observable network and acknowledged mutations. Implementations must
/// bound operation time and raise on failure; they must not silently replace.
pub(open) trait NetworkBackend {
  async fn snapshot(Self) -> @state.NetworkSnapshot
  async fn execute(Self, @state.Change) -> Unit
}

///|
/// Adapter over a caller-owned RouteClient. The caller remains responsible for
/// closing the client; reconciliation serializes operations, not other users.
pub struct RouteBackend {
  client : @transport.RouteClient
}

///|
pub fn RouteBackend::new(client : @transport.RouteClient) -> RouteBackend {
  { client, }
}

///|
pub extend RouteBackend with NetworkBackend::{snapshot, execute}

///|
pub impl NetworkBackend for RouteBackend with fn snapshot(self) {
  @state.NetworkSnapshot::new(
    links=self.client.get_links(),
    addresses=self.client.get_addresses(),
    routes=self.client.get_routes(),
    neighbors=self.client.get_neighbors(),
  )
}

///|
pub impl NetworkBackend for RouteBackend with fn execute(self, change) {
  let mode : @route.AddMode = Exclusive
  let link = self.client.get_link_by_name(change.interface_name())
  if link.index != change.interface_index() {
    raise @state.SafetyError::StaleInterface(
      interface=change.interface_name(),
      planned_index=change.interface_index(),
      observed_index=Some(link.index),
    )
  }
  match change {
    SetLinkUp(index~, after~, ..) =>
      if after {
        self.client.set_link_up(index)
      } else {
        self.client.set_link_down(index)
      }
    SetMtu(index~, after~, ..) => self.client.set_link_mtu(index, after)
    AddAddress(spec~, ..) => self.client.add_address(spec, mode~)
    DeleteAddress(spec~, ..) => self.client.delete_address(spec)
    AddRoute(spec~, ..) => self.client.add_route(spec, mode~)
    DeleteRoute(spec~, ..) => self.client.delete_route(spec)
  }
}
