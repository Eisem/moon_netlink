///|
/// Validate the entire owned plan before writing. Dry-run is the default.
/// Stop on the first failed operation and retain its original typed error.
/// Shield each bounded mutation from cancellation to account for its ACK;
/// cancellation between operations stops further changes and is reported.
pub async fn apply_plan(
  backend : &NetworkBackend,
  plan : @state.Plan,
  dry_run? : Bool = true,
  dangerous? : Bool = false,
) -> ApplyReport {
  let plan = plan.copy()
  @state.validate_plan(plan, backend.snapshot(), dangerous~)
  let completed : Array[Int] = []
  let mut failed : StepFailure? = None
  let cancelled = if dry_run {
    false
  } else {
    @async.handle_cancellation(() => {
      for index, step in plan.steps {
        @async.protect_from_cancel(() => backend.execute(step.change)) catch {
          error => {
            let outcome_unknown = match error {
              @transport.TransportError::KernelRejected(..)
              | @transport.TransportError::KernelRejectedDetailed(..)
              | @state.SafetyError::StaleInterface(..) => false
              _ => true
            }
            failed = Some({ index, error, outcome_unknown, })
            break
          }
        }
        completed.push(index)
        @async.pause()
      }
    })
    is None
  }
  let attempted = completed.length() + (if failed is Some(_) { 1 } else { 0 })
  let rollback = if !dry_run && (failed is Some(_) || cancelled) {
    @async.protect_from_cancel(() => {
      rollback_completed(backend, plan, completed)
    })
  } else {
    []
  }
  {
    plan,
    completed,
    failed,
    not_executed: [
      for index in attempted..<plan.steps.length() => index
    ],
    dry_run,
    cancelled,
    rollback,
    verification: None,
  }
}
