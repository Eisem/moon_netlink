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
ip link set testveth up
ip address add 192.0.2.99/24 dev testveth
ip address add 192.0.2.20/24 dev testveth
ip route add 198.51.101.0/24 dev testveth table 1000 metric 41 proto static
python3 - <<'PY'
import json
import pathlib
import subprocess
import tempfile

binary = pathlib.Path('_build/native/debug/build/cmd/moonnet/moonnet.exe').resolve()
def run(*args, success=True):
    result = subprocess.run([str(binary), *args], text=True, capture_output=True, timeout=45)
    assert (result.returncode == 0) == success, (args, result.stdout, result.stderr)
    return result
def ip(*args):
    return json.loads(subprocess.check_output(['ip', '-j', *args], text=True, timeout=10))
def address_set():
    return {row['local'] for row in ip('address', 'show', 'dev', 'testveth')[0]['addr_info']}
def configured_link(name='testveth'):
    row = ip('link', 'show', 'dev', name)[0]
    return row['mtu'], 'UP' in row['flags']

with tempfile.TemporaryDirectory(prefix='moonnet-failures-') as directory:
    path = pathlib.Path(directory) / 'desired.json'
    before_link = configured_link()
    before_peer = configured_link('testpeer')
    before_routes = ip('-4', 'route', 'show', 'table', '1000')
    conflict = {'schema_version': 1, 'links': [
        {'name': 'testveth', 'ensure': 'present', 'mtu': 1400},
        {'name': 'testveth', 'ensure': 'present', 'mtu': 1300}]}
    path.write_text(json.dumps(conflict), encoding='utf-8')
    rejected = run('apply', str(path), '--yes', '--json', success=False)
    assert not rejected.stdout and 'ConflictingIntent' in rejected.stderr, rejected
    assert configured_link() == before_link
    guarded = {'schema_version': 1, 'links': [{'name': 'testveth', 'ensure': 'present', 'mtu': 1400}],
               'routes': [{'interface': 'testveth', 'ensure': 'present', 'destination': '0.0.0.0', 'prefix_length': 0}]}
    path.write_text(json.dumps(guarded), encoding='utf-8')
    rejected = run('apply', str(path), '--yes', '--json', success=False)
    assert not rejected.stdout and 'default route' in rejected.stderr
    assert configured_link() == before_link, 'protected plan performed an earlier write'
    desired = {'schema_version': 1,
        'links': [{'name': 'testveth', 'ensure': 'present', 'up': True, 'mtu': 1400},
                  {'name': 'testpeer', 'ensure': 'present', 'up': True}],
        'addresses': [dict(interface='testveth', ensure=ensure, address=address, prefix_length=prefix)
                      for ensure, address, prefix in [('absent', '192.0.2.20', 24), ('present', '192.0.2.10', 24), ('present', '2001:db8:10::10', 64)]],
        'routes': [
            {'interface': 'testveth', 'ensure': 'absent', 'destination': '198.51.101.0', 'prefix_length': 24, 'table': 1000, 'priority': 41},
            {'interface': 'testveth', 'ensure': 'present', 'destination': '198.51.100.0', 'prefix_length': 24, 'table': 1000, 'priority': 42},
            {'interface': 'testveth', 'ensure': 'present', 'destination': '198.51.200.0', 'prefix_length': 24, 'gateway': '198.18.0.1', 'table': 1000, 'priority': 43},
            {'interface': 'testveth', 'ensure': 'present', 'destination': '2001:db8:20::', 'prefix_length': 64, 'table': 1000, 'priority': 44}]}
    path.write_text(json.dumps(desired), encoding='utf-8')
    preview = json.loads(run('plan', str(path), '--json').stdout)
    failed_index = next(index for index, step in enumerate(preview['steps'])
                        if step['change'].get('destination') == '198.51.200.0')
    assert failed_index < len(preview['steps']) - 1, preview
    assert any(step['change'].get('destination') == '198.51.100.0'
               for step in preview['steps'][:failed_index]), preview
    result = run('apply', str(path), '--yes', '--json', success=False)
    report = json.loads(result.stdout)
    assert not report['succeeded'] and not report['verification']['satisfied'], report
    assert report['failed']['index'] == failed_index and report['failed']['error']['errno'] == 101, report
    assert not report['failed']['outcome_unknown']
    assert report['completed'] == list(range(failed_index)), report
    assert report['not_executed'] == list(range(failed_index + 1, len(preview['steps']))), report
    assert [item['index'] for item in report['rollback']] == list(reversed(range(failed_index))), report
    assert all(item['status'] == 'completed' for item in report['rollback']), report
    assert configured_link() == before_link
    assert configured_link('testpeer') == before_peer
    assert {'192.0.2.20', '192.0.2.99'} <= address_set(), address_set()
    assert '192.0.2.10' not in address_set() and '2001:db8:10::10' not in address_set()
    assert ip('-4', 'route', 'show', 'table', '1000') == before_routes
    assert not any(row.get('table') in (1000, '1000') for row in ip('-6', 'route', 'show', 'table', 'all'))
    assert report['verification']['remaining']['steps'], report
    human = run('apply', str(path), '--yes', success=False).stdout
    assert 'Apply failed' in human and 'compensation' in human and 'desired state unmet' in human
    assert configured_link() == before_link and ip('-4', 'route', 'show', 'table', '1000') == before_routes
print('isolated conflict/protection and kernel mid-plan failure: original cause, reverse compensation, restored supported configuration: ok')
PY
NAMESPACE
