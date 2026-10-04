///|
async fn collect_snapshot(
  client : @transport.RouteClient,
) -> @state.NetworkSnapshot {
  @state.NetworkSnapshot::new(
    links=client.get_links(),
    addresses=client.get_addresses(),
    routes=client.get_routes(),
    neighbors=client.get_neighbors(),
  )
}

///|
async fn print_snapshot() -> Unit {
  @async.with_task_group(group => {
    let client = @transport.RouteClient::open()
    group.add_defer(() => @async.protect_from_cancel(() => client.close()))
    println(collect_snapshot(client).to_json().stringify())
  })
}
