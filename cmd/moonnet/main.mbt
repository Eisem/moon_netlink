///|
enum ObjectKind {
  Link
  Address
  Route
  Neighbor
}

///|
struct CliOptions {
  kind : ObjectKind
  json : Bool
}

///|
fn usage() -> String {
  (
    #|MoonNetlink read-only CLI
    #|
    #|Usage:
    #|  moonnet link show [--json]
    #|  moonnet address show [--json]
    #|  moonnet route show [--json]
    #|  moonnet neighbor show [--json]
    #|  moonnet watch [link|address|route|neighbor|all] [--jsonl]
    #|  moonnet snapshot
    #|  moonnet plan desired.json [--json] [--dangerous]
    #|  moonnet apply desired.json [--json] [--dangerous]  (dry-run)
  )
}

///|
fn parse_cli_args(args : ArrayView[String]) -> CliOptions? {
  if args.length() != 3 && args.length() != 4 {
    return None
  }
  if args[2] != "show" || (args.length() == 4 && args[3] != "--json") {
    return None
  }
  let kind = match args[1] {
    "link" => Link
    "address" => Address
    "route" => Route
    "neighbor" => Neighbor
    _ => return None
  }
  Some({ kind, json: args.length() == 4, })
}

///|
async fn run_cli() -> Unit {
  let args = @env.args()
  if args.length() >= 2 && (args[1] == "plan" || args[1] == "apply") {
    guard parse_plan_args(args) is Some(options) else { fail(usage()) }
    run_plan_cli(options)
    return
  }
  if args.length() == 2 && args[1] == "snapshot" {
    print_snapshot()
    return
  }
  if args.length() >= 2 && args[1] == "watch" {
    guard parse_watch_args(args) is Some(options) else { fail(usage()) }
    watch_events(options)
    return
  }
  guard parse_cli_args(@env.args()) is Some(options) else { fail(usage()) }
  let client = @transport.RouteClient::open()
  let output = match options.kind {
    Link => format_links(client.get_links(), options.json)
    Address => format_addresses(client.get_addresses(), options.json)
    Route => format_routes(client.get_routes(), options.json)
    Neighbor => format_neighbors(client.get_neighbors(), options.json)
  }
  client.close()
  println(output)
}

///|
#warnings("-fragile_catch_all")
async fn main {
  run_cli() catch {
    error => {
      let text = match error {
        @transport.TransportError::KernelRejected(errno~) =>
          "kernel rejected request (errno \{errno})"
        @transport.TransportError::KernelRejectedDetailed(errno~, extack~, ..) =>
          "kernel rejected request (errno \{errno}): \{extack.message.unwrap_or("no diagnostic text")} (offset \{Repr(extack.offset)})"
        @transport.TransportError::EventStreamLost =>
          "monitor lost events; query a fresh snapshot before resuming"
        _ => "\{Repr(error)}"
      }
      @stdio.stderr.write("moonnet: \{text}\n")
      raise error
    }
  }
}
