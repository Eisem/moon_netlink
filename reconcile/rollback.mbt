///|
pub(all) enum CompensationStatus {
  Completed
  Failed(Error)
  Unavailable(String)
}

///|
pub struct RollbackResult {
  index : Int
  change : @state.Change?
  status : CompensationStatus
}

///|
fn inverse(change : @state.Change) -> @state.Change? {
  match change {
    SetLinkUp(name~, index~, before~, after~) =>
      Some(SetLinkUp(name~, index~, before=after, after=before))
    SetMtu(name~, index~, before=Some(old), after~) =>
      Some(SetMtu(name~, index~, before=Some(after), after=old))
    SetMtu(before=None, ..) => None
    AddAddress(name~, spec~) => Some(DeleteAddress(name~, spec~))
    DeleteAddress(name~, spec~) => Some(AddAddress(name~, spec~))
    AddRoute(name~, spec~) => Some(DeleteRoute(name~, spec~))
    DeleteRoute(name~, spec~) => Some(AddRoute(name~, spec~))
  }
}

///|
async fn rollback_completed(
  backend : &NetworkBackend,
  plan : @state.Plan,
  completed : Array[Int],
) -> Array[RollbackResult] {
  let result = []
  for index in completed.rev() {
    let change = inverse(plan.steps[index].change)
    let status = match change {
      None => Unavailable("previous MTU was not observed")
      Some(operation) =>
        try backend.execute(operation) catch {
          error => Failed(error)
        } noraise {
          _ => Completed
        }
    }
    result.push({ index, change, status, })
  }
  result
}
