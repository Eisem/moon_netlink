# Ordered reconciliation

`NetworkBackend` separates observable snapshots and bounded acknowledged
mutations. `RouteBackend::new(client)` adapts the public SDK; callers close the
client. It rechecks interface name/index immediately before each SDK mutation,
but cannot make kernel changes atomic or stop independent writers.

`apply_plan(backend, plan, dry_run=true, dangerous=false)` owns a copy of the
step array and runs shared whole-plan protection before any mutation. Explicit
execution follows Plan order and stops on its first error. `ApplyReport` exposes
acknowledged indices, the original typed error, remaining indices, dry-run and
cancellation state. JSON preserves kernel errno/extack fields. An unknown
failed-operation outcome is marked explicitly; a timeout can follow a successful
kernel write. Acknowledgement does not prove that desired state was achieved.

Mutations are shielded from caller cancellation until their bounded SDK request
finishes; cancellation between steps stops execution. Custom backends must bound
their own operations. On failure or cancellation, completed operations are
compensated in reverse order under cancellation protection. Compensation errors
are recorded without hiding the original error or stopping later compensations.
Unobserved previous MTU is explicitly unavailable. An unacknowledged failed
operation is never blindly compensated because its outcome may be unknown.

Compensation restores supported managed fields/identities, not arbitrary kernel
metadata, address lifetimes or implicit connected-route effects. Independent
writers can make compensation fail. This is best-effort recovery, not an atomic
transaction; final desired-state verification is still a separate task.
