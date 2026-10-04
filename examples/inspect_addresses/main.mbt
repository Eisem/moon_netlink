///|
async fn main {
  let client = @transport.RouteClient::open()
  let addresses = client.get_addresses()
  for address in addresses {
    let value = match address.local_address {
      Some(value) => Some(value)
      None => address.address
    }
    println(
      "address family=\{Repr(address.family)} index=\{address.interface_index} interface=\{Repr(address.interface_name)} prefix=\{address.prefix_length.to_int()} value=\{Repr(value)}",
    )
  }
  client.close()
}
