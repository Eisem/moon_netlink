///|
fn format_apply_report(report : @reconcile.ApplyReport, json : Bool) -> String {
  if json {
    return report.to_json().stringify()
  }
  let lines = [
    "Apply \{if report.succeeded() { "succeeded" } else { "failed" }}: \{report.completed.length()} acknowledged operation(s)",
  ]
  for index in report.completed {
    lines.push(
      "completed \{index + 1}: \{report.plan.steps[index].change.to_json().stringify()}",
    )
  }
  if report.failed is Some(failure) {
    lines.push(
      "failed \{failure.index + 1}: \{Repr(failure.error)}; outcome unknown=\{failure.outcome_unknown}",
    )
  }
  for index in report.not_executed {
    lines.push("not executed: \{index + 1}")
  }
  if report.cancelled {
    lines.push("execution cancelled")
  }
  for item in report.rollback {
    let status = match item.status {
      Completed => "completed"
      Failed(error) => "failed: \{Repr(error)}"
      Unavailable(reason) => "unavailable: \{reason}"
    }
    lines.push("compensation \{item.index + 1}: \{status}")
  }
  if report.verification is Some(result) {
    if result.error is Some(error) {
      lines.push("final verification error: \{Repr(error)}")
    } else if result.satisfied() {
      lines.push("final verification: desired state satisfied")
    } else if result.remaining is Some(plan) {
      lines.push(
        "final verification: desired state unmet\n\{format_plan(plan, false)}",
      )
    }
  }
  lines.join("\n")
}
