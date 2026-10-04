///|
pub struct StepFailure {
  index : Int
  error : Error
  outcome_unknown : Bool
}

///|
/// Completed means acknowledged; it does not yet prove final desired state.
pub struct ApplyReport {
  plan : @state.Plan
  completed : Array[Int]
  failed : StepFailure?
  not_executed : Array[Int]
  dry_run : Bool
  cancelled : Bool
  rollback : Array[RollbackResult]
  verification : VerificationResult?
}

///|
pub fn ApplyReport::completed_without_error(self : ApplyReport) -> Bool {
  !self.dry_run &&
  !self.cancelled &&
  self.failed is None &&
  self.completed.length() == self.plan.steps.length()
}

///|
/// Success requires both acknowledged execution and a fresh desired-state check.
pub fn ApplyReport::succeeded(self : ApplyReport) -> Bool {
  self.completed_without_error() &&
  self.verification.map(result => result.satisfied()).unwrap_or(false)
}

///|
fn error_json(error : Error) -> Json {
  match error {
    @transport.TransportError::RequestTimedOut(timeout_ms~) =>
      { "kind": "timeout", "timeout_ms": @json.to_json(timeout_ms) }
    @transport.TransportError::KernelRejected(errno~) =>
      { "kind": "kernel", "errno": @json.to_json(errno) }
    @transport.TransportError::KernelRejectedDetailed(errno~, extack~, ..) =>
      {
        "kind": "kernel",
        "errno": @json.to_json(errno),
        "message": @json.to_json(extack.message),
        "offset": @json.to_json(extack.offset),
      }
    @state.SafetyError::StaleInterface(
      interface~,
      planned_index~,
      observed_index~
    ) =>
      {
        "kind": "stale_interface",
        "interface": Json::string(interface),
        "planned_index": @json.to_json(planned_index),
        "observed_index": @json.to_json(observed_index),
      }
    _ => { "kind": "operation", "detail": Json::string("\{Repr(error)}") }
  }
}

///|
pub fn ApplyReport::to_json(self : ApplyReport) -> Json {
  {
    "schema_version": 1,
    "plan": self.plan.to_json(),
    "completed": @json.to_json(self.completed),
    "failed": match self.failed {
      None => Json::null()
      Some(failure) =>
        {
          "index": @json.to_json(failure.index),
          "error": error_json(failure.error),
          "outcome_unknown": Json::boolean(failure.outcome_unknown),
        }
    },
    "not_executed": @json.to_json(self.not_executed),
    "dry_run": Json::boolean(self.dry_run),
    "cancelled": Json::boolean(self.cancelled),
    "rollback": Json::array(
      [
        for item in self.rollback => {
          {
            "index": @json.to_json(item.index),
            "change": item.change
            .map(change => change.to_json())
            .unwrap_or(Json::null()),
            "status": Json::string(
              match item.status {
                Completed => "completed"
                Failed(_) => "failed"
                Unavailable(_) => "unavailable"
              },
            ),
            "error": match item.status {
              Failed(error) => error_json(error)
              _ => Json::null()
            },
            "reason": match item.status {
              Unavailable(reason) => Json::string(reason)
              _ => Json::null()
            },
          }
        }
      ],
    ),
    "execution_completed": Json::boolean(self.completed_without_error()),
    "succeeded": Json::boolean(self.succeeded()),
    "verification": self.verification
    .map(result => result.to_json())
    .unwrap_or(Json::null()),
  }
}
