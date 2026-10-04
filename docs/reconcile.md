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
transaction.

`reconcile(backend, desired, dry_run=true, dangerous=false)` owns the desired
arrays, builds a fresh plan, executes it with the same safeguards, and queries
again after execution or compensation. Verification contains the observation,
remaining plan or its original read/comparison error. `succeeded()` requires
acknowledged execution and an empty final desired-state difference; it remains
false after a mutation failure, cancellation, unmet goals or verification error.
Dry-run has no final verification. The lower-level `apply_plan` reports ACKs
only, so its `succeeded()` is always false without a desired-state verification.
A verification error alone does not blindly compensate already acknowledged
changes; the report exposes the uncertainty for caller recovery.
