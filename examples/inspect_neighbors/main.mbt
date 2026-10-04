///|
async fn main {
  let client = @transport.RouteClient::open()
  let neighbors = client.get_neighbors()
  println("neighbors=\{neighbors.length()}")
  for neighbor in neighbors {
    let destination = match neighbor.destination {
      Some(value) => value.to_string()
      None => "-"
    }
    let link_layer_address = match neighbor.link_layer_address {
      Some(value) => value.to_string()
      None => "-"
    }
    println(
      "neighbor family=\{Repr(neighbor.family)} index=\{neighbor.interface_index} interface=\{Repr(neighbor.interface_name)} destination=\{destination} lladdr=\{link_layer_address} state=\{Repr(neighbor.state)}",
    )
  }
  client.close()
}
