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
    result = subprocess.run([str(binary), *args], text=True, capture_output=True, timeout=15)
    assert (result.returncode == 0) == success, (args, result.stdout, result.stderr)
    return result

def observed():
    return [json.loads(subprocess.check_output(['ip', '-j', *args], text=True))
            for args in [('link',), ('address',), ('route', 'show', 'table', 'all'), ('neigh',)]]

with tempfile.TemporaryDirectory(prefix='moonnet-plan-') as directory:
    path = pathlib.Path(directory) / 'desired.json'
    path.write_text(json.dumps({'schema_version': 1,
        'links': [{'name': 'testveth', 'ensure': 'present', 'up': True, 'mtu': 1400}],
        'addresses': [dict(interface='testveth', ensure='present', address=address, prefix_length=prefix)
                      for address, prefix in [('192.0.2.10', 24), ('2001:db8:10::10', 64)]],
        'routes': [{'interface': 'testveth', 'ensure': 'present', 'destination': '198.51.100.0', 'prefix_length': 24}]
    }), encoding='utf-8')
    before = observed()
    plan = json.loads(run('plan', str(path), '--json').stdout)
    assert plan == json.loads(run('apply', str(path), '--json').stdout)
    assert len(plan['steps']) == 5, plan
    assert all(step['reason'] and not step['dangerous'] for step in plan['steps'])
    assert 'no changes applied' in run('plan', str(path)).stdout
    assert observed() == before, 'dry-run changed network'
    path.write_text('{"schema_version":1,"links":[{"name":"lo","ensure":"present","up":false}]}')
    run('plan', str(path), '--json', success=False)
    protected = json.loads(run('plan', str(path), '--dangerous', '--json').stdout)
    assert protected['steps'][0]['dangerous']
    run('apply', str(path), '--yes', success=False)
    path.write_text('{"schema_version":1,"unknown":true}')
    run('plan', str(path), success=False)
    assert observed() == before, 'rejection changed network'
print('isolated plan/unconfirmed apply: equal plans, strict errors, protection, no mutation: ok')
PY
NAMESPACE
