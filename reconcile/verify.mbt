///|
pub struct VerificationResult {
  snapshot : @state.NetworkSnapshot?
  remaining : @state.Plan?
  error : Error?
}

///|
pub fn VerificationResult::satisfied(self : VerificationResult) -> Bool {
  self.error is None &&
  self.remaining.map(plan => plan.steps.is_empty()).unwrap_or(false)
}

///|
pub fn VerificationResult::to_json(self : VerificationResult) -> Json {
  {
    "satisfied": Json::boolean(self.satisfied()),
    "snapshot": self.snapshot
    .map(snapshot => snapshot.to_json())
    .unwrap_or(Json::null()),
    "remaining": self.remaining
    .map(plan => plan.to_json())
    .unwrap_or(Json::null()),
    "error": self.error.map(error => error_json(error)).unwrap_or(Json::null()),
  }
}

///|
/// Observe, plan, execute/compensate, then freshly observe and compare. A final
/// read or comparison failure is recorded separately from mutation failures.
/// Dry-run performs no final execution verification and is never apply success.
pub async fn reconcile(
  backend : &NetworkBackend,
  desired : @state.DesiredState,
  dry_run? : Bool = true,
  dangerous? : Bool = false,
) -> ApplyReport {
  let desired = desired.copy()
  let plan = @state.build_plan(backend.snapshot(), desired)
  let report = apply_plan(backend, plan, dry_run~, dangerous~)
  if dry_run {
    return report
  }
  let verification = @async.protect_from_cancel(() => {
    try {
      let snapshot = backend.snapshot()
      {
        snapshot: Some(snapshot),
        remaining: Some(@state.build_plan(snapshot, desired)),
        error: None,
      }
    } catch {
      error => { snapshot: None, remaining: None, error: Some(error), }
    }
  })
  { ..report, verification: Some(verification), }
}
