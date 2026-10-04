"""Mutation and JSONL monitor acceptance test; called only by unshare -Urn."""

import json
import os
import queue
import signal
import subprocess
import threading
import time


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=45)
    if result.returncode:
        raise AssertionError(f"{args} exited {result.returncode}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def ip_json(*args):
    return json.loads(run("ip", "-j", *args))


def moon(*args):
    return run("moon", "run", "--target", "native", *args)


def feed_lines(pipe, output):
    for line in pipe:
        output.put(line)


def start_watch(kind):
    process = subprocess.Popen(
        ["moon", "run", "--target", "native", "cmd/moonnet", "--", "watch", kind, "--jsonl"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True,
    )
    output, errors = queue.Queue(), queue.Queue()
    threading.Thread(target=feed_lines, args=(process.stdout, output), daemon=True).start()
    threading.Thread(target=feed_lines, args=(process.stderr, errors), daemon=True).start()
    deadline = time.monotonic() + 30
    diagnostics = []
    try:
        while time.monotonic() < deadline:
            line = errors.get(timeout=max(0.01, deadline - time.monotonic()))
            diagnostics.append(line)
            if line.strip() == "moonnet watch: ready":
                return process, output
        raise AssertionError("monitor did not subscribe: " + "".join(diagnostics))
    except BaseException:
        stop_watch(process)
        raise


def stop_watch(process):
    # Stop both moon run and its executable so no child keeps the namespace.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=5)
    process.stdout.close()
    process.stderr.close()


def collect(output, predicate):
    events = []
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        try:
            line = output.get(timeout=max(0.01, deadline - time.monotonic()))
        except queue.Empty:
            break
        event = json.loads(line)
        assert set(event) == {"event", "object"}, event
        events.append(event)
        if predicate(events):
            return events
    raise AssertionError("missing expected monitor events: " + json.dumps(events))


def main():
    parent = os.environ.get("MOONNETLINK_TEST_PARENT_NETNS")
    assert parent and os.readlink("/proc/self/ns/net") != parent, "requires the isolated namespace test wrapper"
    all_watch, all_output = start_watch("all")
    neighbor_watch = None
    try:
        neighbor_watch, neighbor_output = start_watch("neighbor")
        print(moon("examples/configure_veth", "--", "testveth", "add", "--yes"), end="")
        link = ip_json("link", "show", "testveth")[0]
        assert link["mtu"] == 1400 and "UP" in link["flags"], link
        addresses = ip_json("address", "show", "testveth")[0]["addr_info"]
        assert any(a["local"] == "192.0.2.10" and a["prefixlen"] == 24 for a in addresses)
        assert any(a["local"] == "2001:db8::10" and a["prefixlen"] == 64 for a in addresses)
        routes4 = ip_json("-4", "route", "show", "table", "1000")
        assert any(r["dst"] == "198.51.100.0/24" and r["gateway"] == "192.0.2.2" and r["metric"] == 42 for r in routes4), routes4
        routes6 = ip_json("-6", "route", "show", "table", "1000")
        assert any(r["dst"] == "2001:db8:1::/64" and r["dev"] == "testveth" for r in routes6), routes6
        run("ip", "neighbor", "add", "192.0.2.1", "lladdr", "02:00:00:00:00:01", "nud", "permanent", "dev", "testveth")
        run("ip", "-6", "neighbor", "add", "2001:db8::1", "lladdr", "02:00:00:00:00:02", "nud", "permanent", "dev", "testveth")
        # Compare SDK dumps with the kernel while the desired objects exist.
        print(run("python3", ".ci/diff_ip_json.py"), end="")
        run("ip", "neighbor", "del", "192.0.2.1", "dev", "testveth")
        run("ip", "-6", "neighbor", "del", "2001:db8::1", "dev", "testveth")
        print(moon("examples/configure_veth", "--", "testveth", "delete", "--yes"), end="")
        link = ip_json("link", "show", "testveth")[0]
        assert link["mtu"] == 1500 and "UP" not in link["flags"], link
        assert ip_json("-4", "route", "show", "table", "1000") == []
        assert ip_json("-6", "route", "show", "table", "1000") == []
        needed = {"link.changed", "address.added", "address.deleted", "route.added", "route.deleted", "neighbor.changed", "neighbor.deleted"}
        events = collect(all_output, lambda rows: needed <= {r["event"] for r in rows}
                         and all(any(r["event"] == kind and r["object"].get("family") == family for r in rows)
                                 for kind in ("address.added", "address.deleted", "route.added", "route.deleted", "neighbor.changed", "neighbor.deleted")
                                 for family in ("ipv4", "ipv6")))
        assert any(r["event"] == "link.changed" and r["object"]["mtu"] == 1400 for r in events)
        neighbors = collect(neighbor_output, lambda rows: {"neighbor.changed", "neighbor.deleted"} <= {r["event"] for r in rows})
        assert all(r["event"].startswith("neighbor.") for r in neighbors)
        print("isolated typed monitor: Link + IPv4/IPv6 Address/Route/Neighbor add/delete and filtering: ok")
    finally:
        if neighbor_watch is not None:
            stop_watch(neighbor_watch)
        stop_watch(all_watch)


if __name__ == "__main__":
    main()
