///|
async fn main {
  let client = @transport.RouteClient::open()
  let routes = client.get_routes()
  for route in routes {
    println(
      "route family=\{Repr(route.family)} destination=\{Repr(route.destination)}/\{route.destination_prefix_length.to_int()} gateway=\{Repr(route.gateway)} oif=\{Repr(route.output_interface)} table=\{route.table}",
    )
  }
  client.close()
}
