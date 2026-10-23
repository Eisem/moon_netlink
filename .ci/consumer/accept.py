"""Accept only registry-installed SDKs, inside a fresh network namespace."""

import json
import os
from pathlib import Path
import selectors
import subprocess
import sys


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True, timeout=30)


def main():
    assert os.readlink('/proc/self/ns/net') != os.environ['MOONNETLINK_TEST_PARENT_NETNS']
    consumer = Path(sys.argv[1]).resolve()
    app = consumer / '_build/native/debug/build/cmd/app/app.exe'
    monitor = consumer / '_build/native/debug/build/cmd/monitor/monitor.exe'
    run('ip', 'link', 'set', 'lo', 'up')
    run('ip', 'link', 'add', 'testveth', 'type', 'veth', 'peer', 'name', 'testpeer')
    run('ip', 'link', 'set', 'testpeer', 'up')
    run('ip', 'address', 'add', '192.0.2.99/24', 'dev', 'testveth')
    desired = {
        'schema_version': 1,
        'links': [{'name': 'testveth', 'ensure': 'present', 'up': True, 'mtu': 1400}],
        'addresses': [dict(interface='testveth', ensure='present', address=address, prefix_length=prefix)
                      for address, prefix in [('192.0.2.10', 24), ('2001:db8:10::10', 64)]],
        'routes': [dict(interface='testveth', ensure='present', destination=address,
                        prefix_length=prefix, table=1000, priority=42)
                   for address, prefix in [('198.51.100.0', 24), ('2001:db8:20::', 64)]],
    }
    config = consumer / 'desired.json'

    def call(command, confirmed=False):
        config.write_text(json.dumps(desired), encoding='utf-8')
        args = [str(app), command, str(config), '--json']
        if confirmed:
            args.append('--yes')
        return json.loads(run(*args).stdout)

    preview = call('apply')
    assert len(preview['steps']) == 6, preview
    link = json.loads(run('ip', '-j', 'link', 'show', 'testveth').stdout)[0]
    assert link['mtu'] == 1500 and 'UP' not in link['flags'], link
    process = subprocess.Popen([str(monitor)], stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    try:
        with selectors.DefaultSelector() as ready:
            ready.register(process.stderr, selectors.EVENT_READ)
            assert ready.select(timeout=15), 'monitor subscription timed out'
            assert process.stderr.readline().strip() == 'consumer monitor: ready'
        first = call('apply', confirmed=True)
        assert first['decision'] == 'converged', first
        assert first['report']['verification']['satisfied'], first
        output, errors = process.communicate(timeout=15)
        assert process.returncode == 0, errors
        assert output.strip() == 'consumer monitor: observed typed MTU change', output
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate(timeout=5)
        process.stdout.close()
        process.stderr.close()
    assert call('plan')['steps'] == []
    second = call('apply', confirmed=True)
    assert second['decision'] == 'converged' and second['report']['completed'] == [], second
    addresses = json.loads(run('ip', '-j', 'address', 'show', 'testveth').stdout)[0]['addr_info']
    assert {'192.0.2.10', '2001:db8:10::10', '192.0.2.99'} <= {row['local'] for row in addresses}
    for family, destination in [('-4', '198.51.100.0/24'), ('-6', '2001:db8:20::/64')]:
        routes = json.loads(run('ip', '-j', family, 'route', 'show', 'table', '1000').stdout)
        assert any(row['dst'] == destination for row in routes), routes
    for resource in desired['addresses'] + desired['routes']:
        resource['ensure'] = 'absent'
    assert call('apply', confirmed=True)['decision'] == 'converged'
    assert call('plan')['steps'] == []
    addresses = json.loads(run('ip', '-j', 'address', 'show', 'testveth').stdout)[0]['addr_info']
    assert '192.0.2.99' in {row['local'] for row in addresses}
    desired = {'schema_version': 1, 'links': [
        {'name': 'lo', 'ensure': 'present', 'up': False},
    ]}
    config.write_text(json.dumps(desired), encoding='utf-8')
    refused = subprocess.run([str(app), 'apply', str(config), '--yes', '--json'],
                             text=True, capture_output=True, timeout=30)
    assert refused.returncode != 0, refused.stdout
    assert 'moonnetlink-mutation-attempts:0' in refused.stderr, refused.stderr
    loopback = json.loads(run('ip', '-j', 'link', 'show', 'lo').stdout)[0]
    assert 'UP' in loopback['flags'], loopback
    print('Registry consumer: dry-run, IPv4/IPv6 apply, typed monitor, idempotence, deletion and protection: ok')


if __name__ == '__main__':
    main()
