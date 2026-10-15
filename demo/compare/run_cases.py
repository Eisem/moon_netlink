#!/usr/bin/env python3
"""Run comparison-contract cases against one implementation side (P5-V2).

The runner seats each case's declared initial state through iproute2, invokes
the selected side for the read-only plan, the unconfirmed apply and the
confirmed apply, and checks the result against `demo/compare/contract.json`
with an independent `ip -j` observation. It must run inside a disposable
network namespace; it refuses to run when the network namespace equals the one
named in `MOONNETLINK_DEMO_PARENT_NETNS`.

It never decides expectations: every value comes from the contract cases, so a
side that drifts from the standard fails rather than redefining it.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))

import check_contract  # noqa: E402  (shared contract loading and projection)

CONTRACT_PATH = HERE / "contract.json"
MANAGED_INTERFACE = "cmpveth"


class Side:
    """One implementation side of the contract."""

    name = "abstract"

    def plan(self, config: str, dangerous: bool = False) -> subprocess.CompletedProcess:
        raise NotImplementedError

    def apply(
        self, config: str, confirmed: bool, dangerous: bool = False
    ) -> subprocess.CompletedProcess:
        raise NotImplementedError

    def document(self, invocation: subprocess.CompletedProcess):
        try:
            return json.loads(invocation.stdout)
        except ValueError:
            return None

    def rejection_document(self, invocation: subprocess.CompletedProcess):
        """Rejections keep stdout empty, like the SDK CLI, and go to stderr."""
        for stream in (invocation.stdout, invocation.stderr):
            try:
                parsed = json.loads(stream)
            except ValueError:
                continue
            if isinstance(parsed, dict) and "reason" in parsed:
                return parsed
        return None

    def plan_steps(self, invocation: subprocess.CompletedProcess) -> list[dict] | None:
        document = self.document(invocation)
        if not isinstance(document, dict) or "steps" not in document:
            return None
        return [
            check_contract.canonical_operation(step["change"]) for step in document["steps"]
        ]

    def rejection_reason(self, invocation: subprocess.CompletedProcess) -> str | None:
        document = self.rejection_document(invocation)
        if document is not None:
            return document["reason"]
        # A side without a structured rejection document is allowed to name the
        # contract's category in its diagnostic instead.
        for reason in check_contract.REJECTION_REASONS:
            if reason in invocation.stderr:
                return reason
        return None

    def attempted_writes(self, invocation: subprocess.CompletedProcess) -> int | None:
        document = self.document(invocation)
        if not isinstance(document, dict):
            return None
        if "attempted_writes" in document:
            return document["attempted_writes"]
        completed = document.get("completed", [])
        failed = document.get("failed")
        return len(completed) + (1 if failed else 0)

    def rejected_write_attempts(self, invocation: subprocess.CompletedProcess) -> int | None:
        document = self.rejection_document(invocation)
        if document is not None and "attempted_writes" in document:
            return document["attempted_writes"]
        return None

    def compensation_indices(self, invocation: subprocess.CompletedProcess) -> list[int]:
        document = self.document(invocation)
        if not isinstance(document, dict):
            return []
        return [item.get("index") for item in document.get("rollback", [])]

    def failure_errno(self, invocation: subprocess.CompletedProcess) -> int | None:
        document = self.document(invocation)
        failed = document.get("failed") if isinstance(document, dict) else None
        if not failed:
            return None
        return failed.get("error", {}).get("errno")

    def failure_message(self, invocation: subprocess.CompletedProcess) -> str:
        document = self.document(invocation)
        failed = document.get("failed") if isinstance(document, dict) else None
        if not failed:
            return ""
        return str(failed.get("error", {}).get("message", ""))

    def extra_checks(self) -> list:
        """Side-specific behaviours that the shared contract does not cover."""
        return []

    def remaining_steps(self, document: dict) -> int | None:
        """Remaining plan length from a report, whatever shape the side uses."""
        verification = document.get("verification") or {}
        if isinstance(verification.get("remaining_steps"), int):
            return verification["remaining_steps"]
        remaining = verification.get("remaining")
        if isinstance(remaining, dict) and isinstance(remaining.get("steps"), list):
            return len(remaining["steps"])
        return None


class ScriptSide(Side):
    """The Bash/iproute2 baseline under `demo/compare/script/`."""

    name = "script"

    #: The mutation that is in flight when an extra check interrupts execution.
    interrupt_step = 3
    #: Seconds the shim holds one mutation, so the signal lands inside it.
    interrupt_delay = 2.0

    def __init__(self) -> None:
        self.entry = HERE / "script" / "baseline.sh"

    def invoke(
        self, *arguments: str, timeout: int = 90, env: dict | None = None
    ) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", str(self.entry), *arguments],
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=timeout,
            env=env,
        )

    def plan(self, config: str, dangerous: bool = False) -> subprocess.CompletedProcess:
        arguments = ["plan", config, "--json"]
        if dangerous:
            arguments.append("--dangerous")
        return self.invoke(*arguments)

    def apply(
        self, config: str, confirmed: bool, dangerous: bool = False
    ) -> subprocess.CompletedProcess:
        arguments = ["apply", config, "--json"]
        if confirmed:
            arguments.append("--yes")
        if dangerous:
            arguments.append("--dangerous")
        return self.invoke(*arguments, timeout=120)

    def shim(self, directory: Path, behaviour: str) -> Path:
        """An `ip` wrapper that reacts to the Nth mutation, not to observations."""
        real = shutil.which("ip")
        marker = directory / "started"
        if behaviour == "self-signal":
            action = 'kill -TERM "$$"\n      exit 143\n'
        else:
            action = f'touch "{marker}"\n      sleep {self.interrupt_delay}\n'
        shim = directory / "ip"
        shim.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            f'real={real!r}\n'
            'if [[ ${1-} == -j ]]; then exec "$real" "$@"; fi\n'
            f'count={str(directory / "count")!r}\n'
            'value=$(cat "$count")\n'
            "value=$((value + 1))\n"
            'printf "%s\\n" "$value" > "$count"\n'
            f"if (( value == {self.interrupt_step} )); then\n"
            f"  {action}"
            "fi\n"
            'exec "$real" "$@"\n',
            encoding="utf-8",
        )
        shim.chmod(0o755)
        return shim

    def extra_checks(self):
        return [
            ("cancellation", self.cancellation_check),
            ("unknown-outcome", self.unknown_outcome_check),
        ]

    def _interrupted_run(self, behaviour: str, problems: list[str]):
        """Run one interrupted apply of the `converge` case."""
        import signal
        import tempfile
        import time

        case = check_contract.load_json(HERE / "cases" / "converge.json")
        config = str((HERE / "cases" / case["desired"]).resolve())
        seat(case)
        with tempfile.TemporaryDirectory(prefix="compare-interrupt-") as workspace:
            directory = Path(workspace)
            (directory / "count").write_text("0\n", encoding="utf-8")
            self.shim(directory, behaviour)
            env = dict(os.environ)
            env["PATH"] = f"{directory}{os.pathsep}{env['PATH']}"
            process = subprocess.Popen(
                ["bash", str(self.entry), "apply", config, "--yes", "--json"],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
            )
            try:
                if behaviour == "cancel":
                    marker = directory / "started"
                    deadline = time.time() + 30
                    while not marker.exists() and time.time() < deadline:
                        time.sleep(0.05)
                    if not marker.exists():
                        process.kill()
                        process.communicate(timeout=10)
                        return None, ["the shim never reached the interrupting mutation"]
                    os.kill(process.pid, signal.SIGTERM)
                stdout, stderr = process.communicate(timeout=60)
            except BaseException:
                process.kill()
                process.communicate(timeout=10)
                raise
        if process.returncode == 0:
            problems.append("an interrupted apply reported success")
        try:
            document = json.loads(stdout)
        except ValueError:
            problems.append(f"an interrupted apply produced no report: {stderr.strip()[:200]}")
            return None, problems
        return document, problems

    def cancellation_check(self) -> list[str]:
        """SIGTERM between steps must stop execution and compensate."""
        problems: list[str] = []
        document, problems = self._interrupted_run("cancel", problems)
        if document is None:
            return problems
        case = check_contract.load_json(HERE / "cases" / "converge.json")
        total = case["expected"]["plan_steps"]
        # The shim counts mutations from one, so mutation `interrupt_step` is
        # step `interrupt_step - 1`. It completes; the trap stops after it.
        expected_completed = list(range(self.interrupt_step))
        if document.get("cancelled") is not True:
            problems.append("cancellation was not reported")
        if document.get("failed") is not None:
            problems.append("a cancelled apply reported a failed operation")
        if document.get("completed") != expected_completed:
            problems.append(
                f"completed {document.get('completed')} differs from {expected_completed}"
            )
        expected_remaining = list(range(self.interrupt_step, total))
        if document.get("not_executed") != expected_remaining:
            problems.append(
                f"not_executed {document.get('not_executed')} differs from {expected_remaining}"
            )
        indices = [item.get("index") for item in document.get("rollback", [])]
        if indices != list(reversed(expected_completed)):
            problems.append(f"compensation {indices} is not the reverse of the completed steps")
        if any(item.get("status") != "completed" for item in document.get("rollback", [])):
            problems.append("a cancellation compensation did not restore its step")
        problems.extend(self._restored(document, total))
        return problems

    def unknown_outcome_check(self) -> list[str]:
        """A signal-terminated command has an unknown outcome and is not compensated."""
        problems: list[str] = []
        document, problems = self._interrupted_run("self-signal", problems)
        if document is None:
            return problems
        case = check_contract.load_json(HERE / "cases" / "converge.json")
        total = case["expected"]["plan_steps"]
        failed_step = self.interrupt_step - 1
        expected_completed = list(range(failed_step))
        if (document.get("failed") or {}).get("outcome_unknown") is not True:
            problems.append("a signal-terminated operation was not reported as unknown")
        if document.get("completed") != expected_completed:
            problems.append(
                f"completed {document.get('completed')} differs from {expected_completed}"
            )
        expected_remaining = list(range(self.interrupt_step, total))
        if document.get("not_executed") != expected_remaining:
            problems.append(
                f"not_executed {document.get('not_executed')} differs from {expected_remaining}"
            )
        if document.get("attempted_writes") != self.interrupt_step:
            problems.append(
                f"attempted writes {document.get('attempted_writes')} differ from "
                f"{self.interrupt_step}"
            )
        indices = [item.get("index") for item in document.get("rollback", [])]
        if indices != list(reversed(expected_completed)):
            problems.append(f"compensation {indices} differs from {list(reversed(expected_completed))}")
        if any(item.get("status") != "completed" for item in document.get("rollback", [])):
            problems.append("a compensation did not restore its step")
        problems.extend(self._restored(document, total))
        return problems

    def _restored(self, document: dict, remaining: int) -> list[str]:
        """The interrupted run must leave the declared initial state behind."""
        problems = []
        observed = self.remaining_steps(document)
        if observed != remaining:
            problems.append(
                f"remaining steps {observed} differ from {remaining}; "
                "the initial state was not restored"
            )
        state = observe()
        case = check_contract.load_json(HERE / "cases" / "converge.json")
        for identity in case["final"]["preserved"]:
            if not holds(identity, state):
                problems.append(f"unmanaged resource {identity} was not preserved")
        return problems


class AppSide(Side):
    """The repository application sample `examples/network_config_app`."""

    name = "app"

    #: Simulated scenario: the business decision the sample must report.
    scenarios = (
        ("partial", "partial"),
        ("unknown", "outcome-unknown"),
        ("compensation", "compensation-failed"),
        ("target-unmet", "target-unmet"),
    )

    def __init__(self) -> None:
        self.binary = (
            ROOT
            / "_build/native/debug/build/examples/network_config_app/network_config_app.exe"
        )

    def invoke(self, *arguments: str, timeout: int = 120) -> subprocess.CompletedProcess:
        if not self.binary.exists():
            raise RuntimeError(f"{self.binary} is missing; run `moon build --target native` first")
        return subprocess.run(
            [str(self.binary), *arguments],
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=timeout,
        )

    def plan(self, config: str, dangerous: bool = False) -> subprocess.CompletedProcess:
        arguments = ["plan", config, "--json"]
        if dangerous:
            arguments.append("--dangerous")
        return self.invoke(*arguments)

    def apply(
        self, config: str, confirmed: bool, dangerous: bool = False
    ) -> subprocess.CompletedProcess:
        arguments = ["apply", config, "--json"]
        if confirmed:
            arguments.append("--yes")
        if dangerous:
            arguments.append("--dangerous")
        return self.invoke(*arguments)

    def document(self, invocation: subprocess.CompletedProcess):
        """The sample wraps the library report in an application document."""
        parsed = super().document(invocation)
        if isinstance(parsed, dict) and "report" in parsed:
            return parsed["report"]
        return parsed

    def wrapper(self, invocation: subprocess.CompletedProcess):
        parsed = super().document(invocation)
        return parsed if isinstance(parsed, dict) else None

    def extra_checks(self):
        return [("simulated-outcomes", self.simulated_check)]

    def simulated_check(self) -> list[str]:
        """The sample must classify simulated failures and never write."""
        problems: list[str] = []
        case = check_contract.load_json(HERE / "cases" / "converge.json")
        config = str((HERE / "cases" / case["desired"]).resolve())
        seat(case)
        expected_completed = [0, 1]
        for mode, decision in self.scenarios:
            result = self.invoke("apply", config, "--json", "--simulate", mode)
            if result.returncode == 0:
                problems.append(f"{mode}: the application accepted a failed simulation")
            document = self.wrapper(result)
            if document is None:
                problems.append(f"{mode}: no application document: {result.stdout[:120]}")
                continue
            if document.get("decision") != decision:
                problems.append(
                    f"{mode}: decision {document.get('decision')!r} differs from {decision!r}"
                )
            if document.get("scenario") != f"simulated:{mode}":
                problems.append(f"{mode}: the run is not labelled as simulated")
            report = document.get("report", {})
            conditions = document.get("conditions", {})
            if conditions.get("outcome_unknown") is not (mode == "unknown"):
                problems.append(f"{mode}: outcome_unknown is not classified as expected")
            if conditions.get("compensation_complete") is (mode == "compensation"):
                problems.append(f"{mode}: compensation_complete is not classified as expected")
            if mode == "target-unmet":
                if report.get("failed") is not None:
                    problems.append("target-unmet: a failure was reported")
                if len(report.get("completed", [])) != case["expected"]["plan_steps"]:
                    problems.append("target-unmet: not every operation was acknowledged")
                if conditions.get("verified") is not False:
                    problems.append("target-unmet: an unchanged kernel was reported verified")
            else:
                if report.get("completed") != expected_completed:
                    problems.append(
                        f"{mode}: completed {report.get('completed')} differs from "
                        f"{expected_completed}"
                    )
                if (report.get("failed") or {}).get("index") != len(expected_completed):
                    problems.append(f"{mode}: the failing step index differs")
            statuses = [item.get("status") for item in report.get("rollback", [])]
            if mode == "compensation" and "failed" not in statuses:
                problems.append("compensation: a failed compensation was not reported")
        state = observe()
        problems.extend(declared_initial_state(case, state))
        for identity in case["final"]["preserved"]:
            if not holds(identity, state):
                problems.append(f"simulated runs modified {identity}")
        return problems


SIDES = {"script": ScriptSide, "app": AppSide}


def ip_json(*arguments: str):
    completed = subprocess.run(
        ["ip", "-j", *arguments], text=True, capture_output=True, timeout=30
    )
    if completed.returncode != 0:
        raise RuntimeError(f"ip -j {' '.join(arguments)} failed: {completed.stderr.strip()}")
    return json.loads(completed.stdout)


def ip(*arguments: str) -> None:
    completed = subprocess.run(["ip", *arguments], text=True, capture_output=True, timeout=30)
    if completed.returncode != 0:
        raise RuntimeError(f"ip {' '.join(arguments)} failed: {completed.stderr.strip()}")


def shell(command: str) -> None:
    completed = subprocess.run(
        command, shell=True, text=True, capture_output=True, timeout=30, cwd=ROOT
    )
    if completed.returncode != 0:
        raise RuntimeError(f"{command!r} failed: {completed.stderr.strip()}")


def reset_topology() -> None:
    subprocess.run(["ip", "link", "del", MANAGED_INTERFACE], capture_output=True, timeout=30)
    ip("link", "add", MANAGED_INTERFACE, "type", "veth", "peer", "name", "cmppeer")
    ip("link", "set", "lo", "up")


def seat(case: dict) -> None:
    reset_topology()
    for link in case["initial"]["links"]:
        name = link["name"]
        if name == "lo" or not link.get("exists", True):
            continue
        if link.get("mtu") is not None:
            ip("link", "set", "dev", name, "mtu", str(link["mtu"]))
        ip("link", "set", "dev", name, "up" if link.get("up") else "down")
    for command in case["initial"].get("fixture", []):
        shell(command)
    for entry in case["initial"]["unmanaged"]:
        shell(entry["command"])


def observe() -> dict:
    links = {}
    for row in ip_json("link", "show"):
        links[row["ifname"]] = {
            "mtu": row.get("mtu"),
            "up": "UP" in row.get("flags", []),
        }
    addresses = set()
    for row in ip_json("address", "show"):
        for info in row.get("addr_info", []):
            addresses.add((row["ifname"], info["local"], info["prefixlen"]))
    routes = set()
    for flag in ("-4", "-6"):
        for row in ip_json(flag, "route", "show", "table", "all"):
            table = row.get("table")
            table = 254 if table is None else {
                "main": 254,
                "local": 255,
                "default": 253,
            }.get(table, int(table) if str(table).isdigit() else None)
            destination = row.get("dst")
            network = None if destination in (None, "default") else str(
                ipaddress.ip_network(destination, strict=False)
            )
            routes.add(
                (
                    row.get("dev"),
                    table,
                    network,
                    row.get("gateway"),
                    row.get("metric") or 0,
                )
            )
    return {"links": links, "addresses": addresses, "routes": routes}


def holds(identity: str, state: dict) -> bool:
    parts = identity.split("|")
    if parts[0] == "link":
        fields = dict(item.split("=") for item in parts[2:])
        link = state["links"].get(parts[1])
        if link is None:
            return False
        return link["mtu"] == int(fields["mtu"]) and link["up"] == (fields["up"] == "true")
    if parts[0] == "address":
        _, interface, address = parts
        address, prefix = address.split("/")
        return (interface, address, int(prefix)) in state["addresses"]
    _, interface, table, destination, gateway, priority = parts
    table = int(table.split("=")[1])
    priority = int(priority.split("=")[1])
    gateway = gateway.split("=")[1]
    gateway = None if gateway == "none" else gateway
    network = str(ipaddress.ip_network(destination, strict=False))
    return any(
        dev == interface
        and observed_table == table
        and observed_network == network
        and (observed_gateway or None) == gateway
        and observed_metric == priority
        for dev, observed_table, observed_network, observed_gateway, observed_metric in state["routes"]
    )


def declared_initial_state(case: dict, state: dict) -> list[str]:
    problems = []
    for link in case["initial"]["links"]:
        if link["name"] == "lo":
            continue
        observed = state["links"].get(link["name"])
        if observed is None:
            problems.append(f"{link['name']} disappeared")
            continue
        if link.get("mtu") is not None and observed["mtu"] != link["mtu"]:
            problems.append(
                f"{link['name']} MTU changed from {link['mtu']} to {observed['mtu']}"
            )
        if link.get("up") is not None and observed["up"] != link["up"]:
            problems.append(f"{link['name']} UP state changed from {link['up']}")
    return problems


def run_case(case: dict, side: Side, notes: list[str]) -> tuple[list[str], dict]:
    problems: list[str] = []
    observed: dict = {"kind": case["kind"]}
    expected = case["expected"]
    config = str((HERE / "cases" / case["desired"]).resolve())
    seat(case)

    plan = side.plan(config)
    plan_steps = side.plan_steps(plan)

    if case["kind"] == "reject":
        if plan.returncode == 0:
            problems.append("a rejected configuration produced a plan")
        reason = side.rejection_reason(plan)
        if reason != expected["rejection"]:
            problems.append(
                f"rejection category {reason!r} differs from {expected['rejection']!r}"
            )
        writes = side.rejected_write_attempts(plan)
        if writes not in (0, None):
            problems.append(f"rejection attempted {writes} write(s)")
        elif writes is None:
            notes.append("this side does not report an attempted-write count for rejections")
        unconfirmed = side.apply(config, confirmed=False)
        if unconfirmed.returncode == 0:
            problems.append("unconfirmed apply accepted a rejected configuration")
        confirmed = side.apply(config, confirmed=True)
        if confirmed.returncode == 0:
            problems.append("confirmed apply accepted a rejected configuration")
        after = observe()
        problems.extend(declared_initial_state(case, after))
        preserved = []
        for identity in case["final"]["preserved"]:
            if not holds(identity, after):
                problems.append(f"unmanaged resource {identity} was not preserved")
            preserved.append(holds(identity, after))
        observed.update(
            {
                "rejection": reason,
                "attempted_writes": writes,
                "preserved": preserved,
                "state_unchanged": not declared_initial_state(case, after),
            }
        )
        return problems, observed

    if plan.returncode != 0:
        problems.append(
            f"plan exited {plan.returncode}: {plan.stderr.strip().splitlines()[:1]}"
        )
        return problems, observed
    declared = [
        check_contract.canonical_operation(operation)
        for operation in expected["operations"]
    ]
    if plan_steps is None:
        problems.append("plan output is not a plan document")
    elif plan_steps != declared:
        problems.append(f"plan differs from the contract: {plan_steps} != {declared}")
    if plan_steps is not None and len(plan_steps) != expected["plan_steps"]:
        problems.append(f"plan has {len(plan_steps)} step(s), expected {expected['plan_steps']}")

    dry_run = side.apply(config, confirmed=False)
    if dry_run.returncode != 0:
        problems.append(f"unconfirmed apply exited {dry_run.returncode}")
    elif side.document(dry_run) != side.document(plan):
        problems.append("unconfirmed apply differs from the plan")
    if side.attempted_writes(dry_run) not in (0, None):
        problems.append("unconfirmed apply attempted a write")
    elif side.attempted_writes(dry_run) is None:
        notes.append("this side does not report an attempted-write count for dry-run")

    result = side.apply(config, confirmed=True)
    document = side.document(result)
    if not isinstance(document, dict):
        problems.append(f"confirmed apply exited {result.returncode} without a report")
        return problems
    if document.get("dry_run") is not False:
        problems.append("a confirmed apply reported itself as a dry run")
    if document.get("cancelled", False) is not False:
        problems.append("a confirmed apply reported cancellation for a contract case")
    completed = document.get("completed", [])
    failed = document.get("failed")
    if completed != expected["completed"]:
        problems.append(f"completed {completed} differs from {expected['completed']}")
    if (failed is None) != (expected["failed"] is None):
        problems.append(f"failed {failed} differs from {expected['failed']}")
    elif failed is not None:
        if failed.get("index") != expected["failed"]["index"]:
            problems.append(f"failed index {failed.get('index')} differs")
        errno = side.failure_errno(result)
        if errno is None:
            notes.append("this side exposes the kernel diagnostic but not the numeric errno")
            if not side.failure_message(result).strip():
                problems.append("a failed operation was reported without any diagnostic")
        elif errno != expected["failed"]["errno"]:
            problems.append(f"failed errno {errno} differs from {expected['failed']['errno']}")
    if document.get("not_executed", []) != expected["not_executed"]:
        problems.append(
            f"not_executed {document.get('not_executed')} differs from {expected['not_executed']}"
        )
    writes = side.attempted_writes(result)
    if writes is None:
        notes.append("this side does not report an attempted-write count")
    elif writes != expected["kernel_write_attempts"]:
        problems.append(
            f"attempted writes {writes} differ from {expected['kernel_write_attempts']}"
        )
    compensations = side.compensation_indices(result)
    if len(compensations) != expected["compensation_attempts"]:
        problems.append(
            f"compensations {compensations} differ from {expected['compensation_attempts']} "
            "attempt(s)"
        )
    elif expected["compensation_attempts"] and compensations != list(
        reversed(expected["completed"])
    ):
        problems.append(f"compensations {compensations} are not the reverse of completed")
    statuses = [
        (item.get("index"), item.get("status")) for item in document.get("rollback", [])
    ]
    if expected["failed"] is not None:
        for index, status in statuses:
            if status != "completed":
                problems.append(
                    f"compensation of step {index} reported {status!r} instead of restoring it"
                )
    verification = document.get("verification", {})
    if bool(verification.get("satisfied")) != expected["verification_satisfied"]:
        problems.append(
            f"verification satisfied={verification.get('satisfied')} differs from "
            f"{expected['verification_satisfied']}"
        )
    if expected["failed"] is not None and side.remaining_steps(document) != case["final"][
        "remaining_steps"
    ]:
        problems.append(
            f"remaining steps {side.remaining_steps(document)} differs from "
            f"{case['final']['remaining_steps']}"
        )
    success_expected = expected["exit_status"] == 0
    if (result.returncode == 0) != success_expected:
        problems.append(
            f"confirmed apply exited {result.returncode}, expected {expected['exit_status']}"
        )

    after = observe()
    preserved = []
    for identity in case["final"]["preserved"]:
        if not holds(identity, after):
            problems.append(f"unmanaged resource {identity} was not preserved")
        preserved.append(holds(identity, after))
    satisfied = []
    for identity in case["final"]["satisfied"]:
        if not holds(identity, after):
            problems.append(f"expected satisfied resource missing: {identity}")
        satisfied.append(holds(identity, after))
    observed.update(
        {
            "plan": plan_steps,
            "completed": completed,
            "failed_index": (failed or {}).get("index"),
            "not_executed": document.get("not_executed", []),
            "attempted_writes": writes,
            "compensations": compensations,
            "verification_satisfied": bool(verification.get("satisfied")),
            "satisfied": satisfied,
            "preserved": preserved,
        }
    )
    return problems, observed


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--side", default="script", choices=sorted(SIDES))
    parser.add_argument("--case", action="append", default=[], help="only this case id")
    parser.add_argument(
        "--exclude", action="append", default=[], help="skip this case id and explain why"
    )
    parser.add_argument("--json", action="store_true")
    options = parser.parse_args(argv[1:])

    parent = os.environ.get("MOONNETLINK_DEMO_PARENT_NETNS")
    problems: list[str] = []
    if not parent:
        problems.append("MOONNETLINK_DEMO_PARENT_NETNS is required; use demo/compare/check.sh")
    elif os.readlink("/proc/self/ns/net") == parent:
        problems.append("refusing to run mutations in the caller's network namespace")

    contract = check_contract.load_json(CONTRACT_PATH)
    case_paths = [HERE / name for name in contract["cases"]]
    selected = [
        path
        for path in case_paths
        if (not options.case or path.stem in options.case) and path.stem not in options.exclude
    ]
    side = SIDES[options.side]()
    results = []
    notes: list[str] = []
    for path in selected:
        case = check_contract.load_json(path)
        observed: dict = {}
        try:
            case_problems, observed = run_case(case, side, notes)
        except Exception as error:  # harness failure, not a product verdict
            case_problems = [f"harness error: {error}"]
        results.append(
            {
                "id": case["id"],
                "status": "failed" if case_problems else "ok",
                "problems": case_problems,
                "observed": observed,
            }
        )
        if not options.json:
            label = "FAILED" if case_problems else "ok"
            print(f"{case['id']:<24} {label}")
            for problem in case_problems:
                print(f"    {problem}")
    for case_id in options.exclude:
        if not options.json:
            print(f"{case_id:<24} skipped (excluded by the caller)")
    for name, check in side.extra_checks():
        try:
            check_problems = check()
        except Exception as error:  # harness failure, not a product verdict
            check_problems = [f"harness error: {error}"]
        results.append(
            {
                "id": name,
                "status": "failed" if check_problems else "ok",
                "problems": check_problems,
            }
        )
        if not options.json:
            label = "FAILED" if check_problems else "ok"
            print(f"{name:<24} {label}")
            for problem in check_problems:
                print(f"    {problem}")
    for note in dict.fromkeys(notes):
        if not options.json:
            print(f"note: {note}")

    failures = [item for item in results if item["problems"]]
    report = {
        "side": side.name,
        "cases": results,
        "excluded": options.exclude,
        "notes": list(dict.fromkeys(notes)),
        "problems": problems,
        "status": "failed" if failures or problems else "ok",
    }
    if options.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        for problem in problems:
            print(f"harness: {problem}", file=sys.stderr)
        print(
            f"\n{side.name} side: {len(results) - len(failures)}/{len(results)} check(s) match the "
            "contract"
        )
    return 1 if failures or problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
