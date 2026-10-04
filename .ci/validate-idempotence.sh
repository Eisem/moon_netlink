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
ip link set testpeer up
ip address add 192.0.2.99/24 dev testveth
ip address add 203.0.113.5/24 dev testpeer
ip route add 198.18.0.0/15 dev testpeer table 1001
python3 - <<'PY'
import json
import pathlib
import subprocess
import tempfile

binary = pathlib.Path('_build/native/debug/build/cmd/moonnet/moonnet.exe').resolve()
def cli(*args):
    result = subprocess.run([str(binary), *args], text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, (args, result.stdout, result.stderr)
    return json.loads(result.stdout)
def ip(*args):
    return json.loads(subprocess.check_output(['ip', '-j', *args], text=True, timeout=10))
def addresses(name):
    return {row['local'] for row in ip('address', 'show', 'dev', name)[0]['addr_info']}
def unmanaged_routes():
    # UP/DOWN on one veth end changes carrier on its peer. Keep every field and
    # every flag except the derived linkdown marker; configured routes must stay.
    return [{**row, 'flags': [flag for flag in row.get('flags', []) if flag != 'linkdown']}
            for row in ip('-4', 'route', 'show', 'table', '1001')]

with tempfile.TemporaryDirectory(prefix='moonnet-idempotence-') as directory:
    path = pathlib.Path(directory) / 'desired.json'
    desired = {'schema_version': 1,
        'links': [{'name': 'testveth', 'ensure': 'present', 'up': True, 'mtu': 1400}],
        'addresses': [dict(interface='testveth', ensure='present', address=address, prefix_length=prefix)
                      for address, prefix in [('192.0.2.10', 24), ('2001:db8:10::10', 64)]],
        'routes': [dict(interface='testveth', ensure='present', destination=destination,
                        prefix_length=prefix, table=1000, priority=priority)
                   for destination, prefix, priority in [('198.51.100.0', 24, 42), ('2001:db8:20::', 64, 43)]]}
    path.write_text(json.dumps(desired), encoding='utf-8')
    unmanaged_route = unmanaged_routes()
    first = cli('apply', str(path), '--yes', '--json')
    assert first['succeeded'] and first['verification']['satisfied'], first
    assert len(first['completed']) == 6, first
    assert {'192.0.2.10', '2001:db8:10::10', '192.0.2.99'} <= addresses('testveth')
    assert '203.0.113.5' in addresses('testpeer')
    assert unmanaged_routes() == unmanaged_route, (unmanaged_route, unmanaged_routes())
    assert any(row['dst'] == '198.51.100.0/24' for row in ip('-4', 'route', 'show', 'table', '1000'))
    assert any(row['dst'] == '2001:db8:20::/64' for row in ip('-6', 'route', 'show', 'table', '1000'))
    assert cli('plan', str(path), '--json')['steps'] == []
    second = cli('apply', str(path), '--yes', '--json')
    assert second['succeeded'] and second['plan']['steps'] == [] and second['completed'] == [], second
    assert unmanaged_routes() == unmanaged_route
    subprocess.run(['python3', '.ci/diff_ip_json.py'], check=True, timeout=60)
    for resource in desired['addresses'] + desired['routes']:
        resource['ensure'] = 'absent'
    desired['links'][0].update(up=False, mtu=1500)
    path.write_text(json.dumps(desired), encoding='utf-8')
    removed = cli('apply', str(path), '--yes', '--json')
    assert removed['succeeded'], removed
    assert cli('plan', str(path), '--json')['steps'] == []
    assert '192.0.2.10' not in addresses('testveth') and '2001:db8:10::10' not in addresses('testveth')
    assert '192.0.2.99' in addresses('testveth') and '203.0.113.5' in addresses('testpeer')
    assert unmanaged_routes() == unmanaged_route
print('isolated IPv4/IPv6 apply, empty second plan/apply, explicit deletion, unmanaged preservation: ok')
PY
NAMESPACE
