///|
/// Application sample: read a declared target, review the plan, execute it
/// explicitly through the public SDK and judge the resulting report.
///
/// Usage (inside a disposable network namespace):
///   network_config_app plan  <config.json> [--json] [--dangerous]
///   network_config_app apply <config.json> [--yes] [--json] [--dangerous]
///                            [--simulate partial|unknown|compensation|target-unmet]
///
/// This is a repository sample, not a replacement for the `moonnet` CLI: it
/// calls the public `state`, `transport` and `reconcile` APIs in process and
/// never shells out. Exit status is zero for a read-only plan or a converged
/// target, and nonzero when the target was refused or not reached; the
/// `decision` field of the JSON document distinguishes those cases.
///
/// Real kernel execution is the default. The `--simulate` scenarios run against
/// a backend that observes the real kernel but answers mutations from a fixed
/// scenario, so failure handling can be exercised without writing anything.

///|
/// Business outcome of one application run.
enum Decision {
  DryRun
  Converged
  TargetUnmet
  Partial
  OutcomeUnknown
  CompensationFailed
  Interrupted
} derive(Debug, Eq)

///|
fn Decision::name(self : Decision) -> String {
  match self {
    DryRun => "dry-run"
    Converged => "converged"
    TargetUnmet => "target-unmet"
    Partial => "partial"
    OutcomeUnknown => "outcome-unknown"
    CompensationFailed => "compensation-failed"
    Interrupted => "interrupted"
  }
}

///|
fn Decision::accepted(self : Decision) -> Bool {
  match self {
    DryRun | Converged => true
    _ => false
  }
}

///|
/// Facts the application reads from the report before deciding anything.
struct Conditions {
  execution_completed : Bool
  verified : Bool
  compensation_complete : Bool
  outcome_unknown : Bool
  cancelled : Bool
} derive(Debug, Eq)

///|
fn Conditions::to_json(self : Conditions) -> Json {
  {
    "execution_completed": Json::boolean(self.execution_completed),
    "verified": Json::boolean(self.verified),
    "compensation_complete": Json::boolean(self.compensation_complete),
    "outcome_unknown": Json::boolean(self.outcome_unknown),
    "cancelled": Json::boolean(self.cancelled),
  }
}

///|
fn compensation_complete(report : @reconcile.ApplyReport) -> Bool {
  for item in report.rollback {
    match item.status {
      Completed => ()
      _ => return false
    }
  }
  true
}

///|
fn conditions_of(report : @reconcile.ApplyReport) -> Conditions {
  {
    execution_completed: report.completed_without_error(),
    verified: report.verification
    .map(result => result.satisfied())
    .unwrap_or(false),
    compensation_complete: compensation_complete(report),
    outcome_unknown: report.failed
    .map(failure => failure.outcome_unknown)
    .unwrap_or(false),
    cancelled: report.cancelled,
  }
}

///|
/// An application decides from the report; acknowledgement alone is not success.
fn classify(report : @reconcile.ApplyReport) -> Decision {
  if report.dry_run {
    DryRun
  } else if report.cancelled {
    Interrupted
  } else if report.failed
    .map(failure => failure.outcome_unknown)
    .unwrap_or(false) {
    OutcomeUnknown
  } else if !compensation_complete(report) {
    CompensationFailed
  } else if report.failed is Some(_) {
    Partial
  } else if report.succeeded() {
    Converged
  } else {
    TargetUnmet
  }
}

///|
struct Options {
  command : String
  path : String
  json : Bool
  dangerous : Bool
  confirmed : Bool
  simulate : SimMode?
}

///|
fn usage() -> String {
  (
    #|Usage (disposable network namespace only):
    #|  network_config_app plan  <config.json> [--json] [--dangerous]
    #|  network_config_app apply <config.json> [--yes] [--json] [--dangerous]
    #|                           [--simulate partial|unknown|compensation|target-unmet]
    #|
    #|apply without --yes prints the same plan as plan and writes nothing.
    #|--simulate never writes to the kernel; it exercises report handling only.
  )
}

///|
fn parse_options(args : ArrayView[String]) -> Options? {
  if args.length() < 3 {
    return None
  }
  let command = args[1]
  if command != "plan" && command != "apply" {
    return None
  }
  if args[2].length() == 0 || args[2].has_prefix("--") {
    return None
  }
  let mut json = false
  let mut dangerous = false
  let mut confirmed = false
  let mut simulate : SimMode? = None
  let mut index = 3
  while index < args.length() {
    match args[index] {
      "--json" if !json => json = true
      "--dangerous" if !dangerous => dangerous = true
      "--yes" if command == "apply" && !confirmed => confirmed = true
      "--simulate" => {
        if command != "apply" ||
          simulate is Some(_) ||
          index + 1 >= args.length() {
          return None
        }
        simulate = match args[index + 1] {
          "partial" => Some(Partial)
          "unknown" => Some(Unknown)
          "compensation" => Some(Compensation)
          "target-unmet" => Some(TargetUnmet)
          _ => return None
        }
        index += 1
      }
      _ => return None
    }
    index += 1
  }
  Some({ command, path: args[2], json, dangerous, confirmed, simulate, })
}

///|
/// Bound the configuration exactly like the CLI: a regular UTF-8 file of at
/// most one MiB, parsed before any socket is opened.
async fn read_desired(path : String) -> @state.DesiredState {
  if @fs.kind(path) != Regular {
    raise @state.StateError::InvalidField(
      path="root",
      reason="configuration must be a regular file",
    )
  }
  if @fs.file_size(path) > 1024 * 1024 {
    raise @state.StateError::InvalidField(
      path="root",
      reason="configuration exceeds 1 MiB",
    )
  }
  @state.DesiredState::parse(@fs.read_file(path).text())
}

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
fn format_plan(plan : @state.Plan, dangerous : Bool) -> String {
  let lines = [
    "Plan: \{plan.steps.length()} operation(s); nothing has been written yet",
  ]
  for index, step in plan.steps {
    let marker = if step.dangerous { " [dangerous]" } else { "" }
    lines.push(
      "\{index + 1}. \{step.change.to_json().stringify()}\{marker}\n   \{step.reason}",
    )
  }
  ignore(dangerous)
  lines.join("\n")
}

///|
/// Read-only path: build the plan from a fresh observation and review it.
async fn show_plan(
  client : @transport.RouteClient,
  desired : @state.DesiredState,
  options : Options,
) -> Unit {
  let snapshot = collect_snapshot(client)
  let plan = @state.build_plan(snapshot, desired)
  @state.validate_plan(plan, snapshot, dangerous=options.dangerous)
  if options.json {
    println(plan.to_json().stringify())
  } else {
    println(format_plan(plan, options.dangerous))
  }
}

///|
fn application_document(
  report : @reconcile.ApplyReport,
  scenario : String,
  conditions : Conditions,
  decision : Decision,
) -> Json {
  {
    "schema_version": 1,
    "application": "network_config_app",
    "scenario": Json::string(scenario),
    "decision": Json::string(decision.name()),
    "conditions": conditions.to_json(),
    "report": report.to_json(),
  }
}

///|
fn format_report(
  report : @reconcile.ApplyReport,
  scenario : String,
  conditions : Conditions,
  decision : Decision,
) -> String {
  let lines = [
    "scenario: \{scenario}",
    "plan: \{report.plan.steps.length()} operation(s)",
  ]
  for index, step in report.plan.steps {
    let marker = if step.dangerous { " [dangerous]" } else { "" }
    lines.push("  \{index + 1}. \{step.change.to_json().stringify()}\{marker}")
  }
  lines.push(
    "acknowledged: \{report.completed.length()}; not executed: \{report.not_executed.length()}; compensations: \{report.rollback.length()}",
  )
  if report.failed is Some(failure) {
    lines.push("failed operation \{failure.index + 1}: \{Repr(failure.error)}")
    lines.push("   outcome unknown=\{failure.outcome_unknown}")
  }
  if report.cancelled {
    lines.push("execution was cancelled between operations")
  }
  for item in report.rollback {
    let status = match item.status {
      Completed => "completed"
      Failed(_) => "failed"
      Unavailable(reason) => "unavailable: \{reason}"
    }
    lines.push("compensation \{item.index + 1}: \{status}")
  }
  lines.push(
    "conditions: execution_completed=\{conditions.execution_completed}, verified=\{conditions.verified}, compensation_complete=\{conditions.compensation_complete}, outcome_unknown=\{conditions.outcome_unknown}",
  )
  lines.push("decision: \{decision.name()}")
  lines.join("\n")
}

///|
/// Print the application document, then fail the process when the application
/// does not accept the outcome. Failing after printing keeps the report
/// available to whoever reads stdout.
fn emit(
  report : @reconcile.ApplyReport,
  scenario : String,
  options : Options,
) -> Unit raise {
  let conditions = conditions_of(report)
  let decision = classify(report)
  if options.json {
    println(
      application_document(report, scenario, conditions, decision).stringify(),
    )
  } else {
    println(format_report(report, scenario, conditions, decision))
  }
  if !decision.accepted() {
    raise ApplicationNotConverged
  }
}

///|
async fn run(options : Options) -> Unit {
  let desired = read_desired(options.path)
  @async.with_task_group(group => {
    let client = @transport.RouteClient::open()
    group.add_defer(() => @async.protect_from_cancel(() => client.close()))
    match options.simulate {
      Some(mode) => {
        let backend = SimulatedBackend::new(client, mode)
        let report = @reconcile.reconcile(
          backend,
          desired,
          dry_run=false,
          dangerous=options.dangerous,
        )
        emit(report, "simulated:\{mode.name()}", options)
      }
      None =>
        if options.command == "apply" && options.confirmed {
          let backend = @reconcile.RouteBackend::new(client)
          let report = @reconcile.reconcile(
            backend,
            desired,
            dry_run=false,
            dangerous=options.dangerous,
          )
          emit(report, "kernel", options)
        } else {
          show_plan(client, desired, options)
        }
    }
  })
}

///|
#warnings("-fragile_catch_all")
async fn main {
  let options = match parse_options(@env.args()) {
    Some(options) => options
    None => fail(usage())
  }
  run(options) catch {
    error => {
      @stdio.stderr.write("network_config_app: \{Repr(error)}\n")
      raise error
    }
  }
}
