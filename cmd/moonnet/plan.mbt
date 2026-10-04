///|
struct PlanOptions {
  path : String
  json : Bool
  dangerous : Bool
  execute : Bool
}

///|
suberror ApplyFailed derive(Debug)

///|
fn parse_plan_args(args : ArrayView[String]) -> PlanOptions? {
  if args.length() < 3 ||
    (args[1] != "plan" && args[1] != "apply") ||
    args[2].length() == 0 ||
    args[2].has_prefix("--") {
    return None
  }
  let mut json = false
  let mut dangerous = false
  let mut execute = false
  for option in args[3:] {
    match option {
      "--json" if !json => json = true
      "--dangerous" if !dangerous => dangerous = true
      "--yes" if args[1] == "apply" && !execute => execute = true
      _ => return None
    }
  }
  Some({ path: args[2], json, dangerous, execute, })
}

///|
async fn read_desired_file(path : String) -> @state.DesiredState {
  if @fs.kind(path) != Regular {
    raise @state.StateError::InvalidField(
      path="root",
      reason="configuration must be a regular file",
    )
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  if file.kind() != Regular {
    raise @state.StateError::InvalidField(
      path="root",
      reason="configuration must be a regular file",
    )
  }
  let limit = 1024 * 1024
  let buffer = FixedArray::make(limit + 1, b'\x00')
  let mut total = 0
  while total < buffer.length() {
    let count = file.read_at(
      buffer,
      position=total.to_int64(),
      offset=total,
      len=buffer.length() - total,
    )
    if count == 0 {
      break
    }
    total += count
  }
  if total > limit {
    raise @state.StateError::InvalidField(
      path="root",
      reason="configuration exceeds 1 MiB",
    )
  }
  let data : &@io.Data = Bytes::from_array(buffer[:total])
  @state.DesiredState::parse(data.text())
}

///|
fn format_plan(plan : @state.Plan, json : Bool) -> String {
  if json {
    return plan.to_json().stringify()
  }
  let lines = [
    "Dry-run: \{plan.steps.length()} operation(s); no changes applied",
  ]
  for index, step in plan.steps {
    lines.push(
      "\{index + 1}. \{step.change.to_json().stringify()}\n   \{step.reason}\{if step.dangerous { " [dangerous]" } else { "" }}",
    )
  }
  lines.join("\n")
}

///|
async fn run_plan_cli(options : PlanOptions) -> Unit {
  // Parse before opening a socket. Confirmation alone enables execution.
  let desired = read_desired_file(options.path)
  @async.with_task_group(group => {
    let client = @transport.RouteClient::open()
    group.add_defer(() => @async.protect_from_cancel(() => client.close()))
    if options.execute {
      let backend = @reconcile.RouteBackend::new(client)
      let report = @reconcile.reconcile(
        backend,
        desired,
        dry_run=false,
        dangerous=options.dangerous,
      )
      println(format_apply_report(report, options.json))
      if !report.succeeded() {
        raise ApplyFailed
      }
      return
    }
    let snapshot = collect_snapshot(client)
    let plan = @state.build_plan(snapshot, desired)
    @state.validate_plan(plan, snapshot, dangerous=options.dangerous)
    println(format_plan(plan, options.json))
  })
}
