///|
/// Phase 0 feasibility probe: ask the Linux kernel for every link and prove
/// that the loopback interface can be decoded without invoking `ip`.
async fn main {
  let client = @transport.RouteClient::open()
  let links = client.get_links()
  let mut found_loopback = false
  for link in links {
    let name = match link.name {
      Some(value) => value
      None => "<unnamed>"
    }
    println(
      "link index=\{link.index} name=\{name} flags=0x\{link.flags.to_string(radix=16)}",
    )
    if name == "lo" {
      found_loopback = true
    }
  }
  if !found_loopback {
    fail("RTM_GETLINK completed but no loopback interface named lo was decoded")
  }
  client.close()
}
