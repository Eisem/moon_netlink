"""Public CLI demonstration, invoked only inside the shell wrapper's namespace."""

import json
import os
import pathlib
import signal
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
BINARY = ROOT / '_build/native/debug/build/cmd/moonnet/moonnet.exe'
DESIRED = ROOT / 'demo/desired.json'


def command(*args, success=True):
    with subprocess.Popen(args, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, start_new_session=True) as process:
        try:
            output, errors = process.communicate(timeout=45)
        except BaseException:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate(timeout=5)
            raise
        if (process.returncode == 0) != success:
            raise RuntimeError(f'{args} exited {process.returncode}\n{output}\n{errors}')
        return subprocess.CompletedProcess(args, process.returncode, output, errors)


def run(*args):
    return command(*args).stdout


def cli(*args):
    return run(str(BINARY), *args)


def ip(*args):
    return json.loads(run('ip', '-j', *args))


def configuration():
    link = ip('link', 'show', 'dev', 'testveth')[0]
    return {
        'mtu': link['mtu'],
        'up': 'UP' in link['flags'],
        'addresses': sorted((a['local'], a['prefixlen'])
                            for a in ip('address', 'show', 'dev', 'testveth')[0]['addr_info']),
        'routes': [r for family in ('-4', '-6')
                   for r in ip(family, 'route', 'show', 'table', 'all')
                   if r.get('table') in (1000, '1000')],
    }


def snapshot(label):
    observation = json.loads(cli('snapshot'))
    print(f'{label}: ' + ', '.join(f'{key}={len(observation[key])}'
                                 for key in ('links', 'addresses', 'routes', 'neighbors')))
    print(json.dumps(configuration(), indent=2))


def main():
    parent = os.environ.get('MOONNETLINK_DEMO_PARENT_NETNS')
    assert parent and os.readlink('/proc/self/ns/net') != parent, 'use bash demo/reconcile.sh'
    print('1. moonnet snapshot (initial configuration)')
    snapshot('Initial snapshot')
    before = configuration()

    print('\n2. moonnet plan demo/desired.json (six operations; dry-run)')
    print(cli('plan', str(DESIRED)), end='')
    plan = json.loads(cli('plan', str(DESIRED), '--json'))
    assert len(plan['steps']) == 6, plan
    unconfirmed = json.loads(cli('apply', str(DESIRED), '--json'))
    assert unconfirmed == plan
    assert configuration() == before, 'dry-run changed configuration'
    print('\nUnconfirmed apply produced the same plan; configuration unchanged.')

    print('\n3. moonnet apply demo/desired.json --yes --json')
    report = json.loads(cli('apply', str(DESIRED), '--yes', '--json'))
    assert report['succeeded'] and report['verification']['satisfied'], report
    assert report['completed'] == list(range(6)) and not report['failed']
    print(json.dumps({key: report[key] for key in
                      ('completed', 'failed', 'not_executed', 'rollback', 'succeeded')}, indent=2))
    print('Final verification: desired state satisfied (fresh SDK queries).')

    print('\n4. moonnet snapshot and independent ip -j comparison')
    snapshot('Final snapshot')
    actual = configuration()
    assert actual['mtu'] == 1400 and actual['up']
    assert ('192.0.2.10', 24) in actual['addresses']
    assert ('2001:db8:10::10', 64) in actual['addresses']
    assert {r['dst'] for r in actual['routes']} == {'198.51.100.0/24', '2001:db8:20::/64'}
    print(run('python3', '.ci/diff_ip_json.py'), end='')

    print('\n5. Second plan and confirmed apply (idempotence)')
    second_plan = json.loads(cli('plan', str(DESIRED), '--json'))
    assert second_plan['steps'] == [], second_plan
    print('Second plan: 0 operations')
    second = json.loads(cli('apply', str(DESIRED), '--yes', '--json'))
    assert second['succeeded'] and second['completed'] == []
    assert second['verification']['satisfied']
    print('Second apply: 0 acknowledged operations; desired state still satisfied.')


if __name__ == '__main__':
    main()
