///|
test "plan and unconfirmed apply share strict options and reject confirmation" {
  for command in ["plan", "apply"] {
    guard parse_plan_args([
        "moonnet", command, "desired.json", "--dangerous", "--json",
      ])
      is Some(options) else {
      fail("valid options rejected")
    }
    assert_true(options.json && options.dangerous)
    assert_eq(options.path, "desired.json")
    for
      flags in [
        ["--yes"],
        ["--json", "--json"],
        ["--dangerous", "--dangerous"],
        ["--unknown"],
        ["extra.json"],
      ] {
      let args = ["moonnet", command, "desired.json"]
      args.append(flags)
      assert_true(parse_plan_args(args) is None)
    }
  }
  assert_true(parse_plan_args(["moonnet", "plan"]) is None)
}

///|
async test "desired file loading is bounded and preserves parser errors" {
  @async.with_task_group(group => {
    let directory = @fs.tmpdir(prefix="moonnet-desired-")
    group.add_defer(() => @fs.rmdir(directory, recursive=true))
    let path = directory + "/desired.json"
    @fs.write_file(path, "{\"schema_version\":1}")
    assert_eq(read_desired_file(path).links.length(), 0)
    @fs.write_file(path, "{\"schema_version\":1,\"unexpected\":0}")
    try read_desired_file(path) catch {
      @state.StateError::InvalidField(..) => ()
      err => fail("unexpected parse error: \{Repr(err)}")
    } noraise {
      _ => fail("unknown field accepted")
    }
    @fs.write_file(path, Bytes::make(1024 * 1024 + 1, b' '))
    try read_desired_file(path) catch {
      @state.StateError::InvalidField(reason="configuration exceeds 1 MiB", ..) =>
        ()
      err => fail("unexpected size error: \{Repr(err)}")
    } noraise {
      _ => fail("oversized file accepted")
    }
  })
}
