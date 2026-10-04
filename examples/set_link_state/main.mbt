///|
fn usage() -> String {
  "Usage: set_link_state <positive-ifindex> <up|down>"
}

///|
async fn main {
  let args = @env.args()
  if args.length() != 3 {
    println(usage())
    return
  }
  let index = @string.parse_int(args[1]) catch {
    _ => {
      println(usage())
      return
    }
  }
  let client = @transport.RouteClient::open()
  match args[2] {
    "up" => client.set_link_up(index)
    "down" => client.set_link_down(index)
    _ => {
      client.close()
      println(usage())
      return
    }
  }
  client.close()
}
