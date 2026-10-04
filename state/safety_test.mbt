///|
test "loopback protection recomputes names and flags despite forged markers" {
  for (name, flags) in [("lo", 1U), ("renamed", 9U)] {
    let snapshot = @state.NetworkSnapshot::new(
      links=[{ ..test_link(7, name), flags, }],
      addresses=[],
      routes=[],
      neighbors=[],
    )
    let plan = @state.build_plan(snapshot, {
      links: [{ name, ensure: Present, up: Some(false), mtu: None, }],
      addresses: [],
      routes: [],
    })
    plan.steps[0] = { ..plan.steps[0], dangerous: false, }
    try @state.validate_plan(plan, snapshot) catch {
      @state.SafetyError::ProtectedResource(reason="loopback", ..) => ()
      err => fail("unexpected error: \{Repr(err)}")
    } noraise {
      _ => fail("loopback accepted")
    }
    @state.validate_plan(plan, snapshot, dangerous=true)
  }
}

///|
test "IPv4 and IPv6 default route add/delete require explicit dangerous" {
  for destination in ["0.0.0.0", "::"] {
    let snapshot = @state.NetworkSnapshot::new(
      links=[test_link(7, "veth0")],
      addresses=[],
      routes=[],
      neighbors=[],
    )
    let plan = @state.build_plan(
      snapshot,
      @state.DesiredState::parse(
        "{\"schema_version\":1,\"routes\":[{\"interface\":\"veth0\",\"ensure\":\"present\",\"destination\":\"\{destination}\",\"prefix_length\":0}]}",
      ),
    )
    for deleting in [false, true] {
      if deleting && plan.steps[0].change is AddRoute(name~, spec~) {
        plan.steps[0] = { ..plan.steps[0], change: DeleteRoute(name~, spec~), }
      }
      try @state.validate_plan(plan, snapshot) catch {
        @state.SafetyError::ProtectedResource(reason="default route", ..) => ()
        err => fail("unexpected error: \{Repr(err)}")
      } noraise {
        _ => fail("default route accepted")
      }
      @state.validate_plan(plan, snapshot, dangerous=true)
    }
  }
}

///|
test "ordinary plans pass but dangerous cannot bypass stale or missing indices" {
  let snapshot = @state.NetworkSnapshot::new(
    links=[test_link(7, "veth0")],
    addresses=[],
    routes=[],
    neighbors=[],
  )
  let plan = @state.build_plan(snapshot, {
    links: [{ name: "veth0", ensure: Present, up: None, mtu: Some(1400), }],
    addresses: [],
    routes: [],
  })
  @state.validate_plan(plan, snapshot)
  for links in [[], [test_link(8, "veth0")]] {
    let changed = @state.NetworkSnapshot::new(links~, addresses=[], routes=[], neighbors=[])
    try @state.validate_plan(plan, changed, dangerous=true) catch {
      @state.SafetyError::StaleInterface(..) => ()
      err => fail("unexpected error: \{Repr(err)}")
    } noraise {
      _ => fail("stale interface accepted")
    }
  }
}
