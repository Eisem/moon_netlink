///|
priv struct WatchOptions {
  filter : String
  jsonl : Bool
}

///|
fn parse_watch_args(args : ArrayView[String]) -> WatchOptions? {
  if args.length() < 2 || args[1] != "watch" {
    return None
  }
  let mut filter : String? = None
  let mut jsonl = false
  for arg in args[2:] {
    match arg {
      "--jsonl" if !jsonl => jsonl = true
      "all" | "link" | "address" | "route" | "neighbor" if filter is None =>
        filter = Some(arg)
      _ => return None
    }
  }
  Some({ filter: filter.unwrap_or("all"), jsonl, })
}

///|
fn event_kind(event : @route.RouteEvent) -> String {
  match event {
    LinkChanged(_) | LinkDeleted(_) => "link"
    AddressAdded(_) | AddressDeleted(_) => "address"
    RouteAdded(_) | RouteDeleted(_) => "route"
    NeighborChanged(_) | NeighborDeleted(_) => "neighbor"
    Unknown(_) => "unknown"
  }
}

///|
fn event_json(event : @route.RouteEvent) -> Json {
  let (kind, value) = match event {
    LinkChanged(link) => ("link.changed", link_json(link))
    LinkDeleted(link) => ("link.deleted", link_json(link))
    AddressAdded(address) => ("address.added", address_json(address))
    AddressDeleted(address) => ("address.deleted", address_json(address))
    RouteAdded(route) => ("route.added", route_json(route))
    RouteDeleted(route) => ("route.deleted", route_json(route))
    NeighborChanged(neighbor) => ("neighbor.changed", neighbor_json(neighbor))
    NeighborDeleted(neighbor) => ("neighbor.deleted", neighbor_json(neighbor))
    Unknown(message) =>
      (
        "unknown",
        {
          "message_type": @json.to_json(message.header.message_type),
          "sequence": @json.to_json(message.header.sequence),
          "flags": @json.to_json(message.header.flags),
          "payload": @json.to_json(
            [
              for byte in message.payload => byte.to_int()
            ],
          ),
        },
      )
  }
  { "event": Json::string(kind), "object": value }
}

///|
async fn watch_events(options : WatchOptions) -> Unit {
  let groups : UInt = match options.filter {
    "link" => 0x0001
    "address" => 0x0110
    "route" => 0x0440
    "neighbor" => 0x0004
    _ => @transport.route_monitor_groups
  }
  let monitor = @transport.RouteMonitor::open(groups~)
  defer monitor.close()
  // This signal goes to stderr; stdout remains an uninterrupted JSONL stream.
  @stdio.stderr.write(b"moonnet watch: ready\n")
  for ;; {
    let event = monitor.next_event()
    if options.filter == "all" || event_kind(event) == options.filter {
      let output = if options.jsonl {
        event_json(event).stringify()
      } else {
        "\{event_kind(event)} \{event.to_repr()}"
      }
      @stdio.stdout.write(output + "\n")
    }
  }
}
