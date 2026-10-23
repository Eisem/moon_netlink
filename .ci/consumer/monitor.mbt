///|
async fn main {
  let monitor = @transport.RouteMonitor::open()
  defer monitor.close()
  @stdio.stderr.write(b"consumer monitor: ready\n")
  for ;; {
    match monitor.next_event() {
      LinkChanged(link) =>
        if link.name == Some("testveth") && link.mtu == Some(1400) {
          @stdio.stdout.write(b"consumer monitor: observed typed MTU change\n")
          break
        }
      _ => ()
    }
  }
}
