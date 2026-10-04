#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in moon unshare ip python3; do command -v "$tool" >/dev/null; done
moon build --target native
export MOONNETLINK_TEST_PARENT_NETNS=$(readlink /proc/self/ns/net)
unshare -Urn -- bash -s <<'NAMESPACE'
set -euo pipefail
test "$(readlink /proc/self/ns/net)" != "$MOONNETLINK_TEST_PARENT_NETNS"
ip link set lo up
ip link add testveth type veth peer name testpeer
python3 - <<'PY'
import json
import pathlib
import subprocess
import tempfile

binary = pathlib.Path('_build/native/debug/build/cmd/moonnet/moonnet.exe').resolve()
def run(*args, success=True):
    result = subprocess.run([str(binary), *args], text=True, capture_output=True, timeout=30)
    assert (result.returncode == 0) == success, (args, result.stdout, result.stderr)
    return result

with tempfile.TemporaryDirectory(prefix='moonnet-apply-') as directory:
    path = pathlib.Path(directory) / 'desired.json'
    path.write_text(json.dumps({'schema_version': 1, 'links': [
        {'name': 'testveth', 'ensure': 'present', 'up': True, 'mtu': 1400}
    ]}), encoding='utf-8')
    preview = json.loads(run('apply', str(path), '--json').stdout)
    assert len(preview['steps']) == 2
    report = json.loads(run('apply', str(path), '--yes', '--json').stdout)
    assert report['succeeded'] and report['verification']['satisfied'], report
    assert report['completed'] == [0, 1] and report['failed'] is None
    link = json.loads(subprocess.check_output(['ip', '-j', 'link', 'show', 'testveth'], text=True))[0]
    assert link['mtu'] == 1400 and 'UP' in link['flags'], link
    assert 'final verification: desired state satisfied' in run('apply', str(path), '--yes').stdout
    path.write_text('{"schema_version":1,"links":[{"name":"lo","ensure":"present","up":false}]}')
    run('apply', str(path), '--yes', '--json', success=False)
    lo = json.loads(subprocess.check_output(['ip', '-j', 'link', 'show', 'lo'], text=True))[0]
    assert 'UP' in lo['flags'], lo
print('isolated confirmed apply: SDK changes, verified JSON/human reports, protection: ok')
PY
NAMESPACE
