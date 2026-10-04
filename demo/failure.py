"""Actual kernel failure and protection, with assertions on recovery and status."""

import json
import os
import pathlib
import tempfile

from reconcile import BINARY, ROOT, cli, command, configuration, ip


def main():
    parent = os.environ.get('MOONNETLINK_DEMO_PARENT_NETNS')
    assert parent and os.readlink('/proc/self/ns/net') != parent, 'use bash demo/failure.sh'
    print('1. Protected loopback operation is refused before any write.')
    with tempfile.TemporaryDirectory(prefix='moonnet-demo-protection-') as directory:
        path = pathlib.Path(directory) / 'protected.json'
        path.write_text(json.dumps({'schema_version': 1, 'links': [
            {'name': 'lo', 'ensure': 'present', 'up': False}]}), encoding='utf-8')
        rejected = command(str(BINARY), 'apply', str(path), '--yes', '--json', success=False)
        assert not rejected.stdout and 'ProtectedResource' in rejected.stderr
        assert 'UP' in ip('link', 'show', 'dev', 'lo')[0]['flags']
        print('ProtectedResource: loopback; nonzero CLI exit; lo remains UP.')

    desired = str(ROOT / 'demo/failure-desired.json')
    print('\n2. Plan includes a gateway outside the connected subnet.')
    print(cli('plan', desired), end='')
    before = configuration()
    print('\n3. Confirmed apply: kernel rejects the sixth operation.')
    failed = command(str(BINARY), 'apply', desired, '--yes', '--json', success=False)
    report = json.loads(failed.stdout)
    assert failed.returncode != 0 and not report['succeeded']
    assert report['failed']['index'] == 5 and report['failed']['error']['errno'] == 101
    assert not report['failed']['outcome_unknown']
    assert report['completed'] == [0, 1, 2, 3, 4] and report['not_executed'] == [6]
    assert [r['index'] for r in report['rollback']] == [4, 3, 2, 1, 0]
    assert all(r['status'] == 'completed' for r in report['rollback'])
    print(json.dumps({key: report[key] for key in
                      ('completed', 'failed', 'not_executed', 'rollback', 'succeeded')}, indent=2))

    print('\n4. Fresh observation: original managed configuration restored.')
    after = configuration()
    assert (after['mtu'], after['up']) == (before['mtu'], before['up'])
    assert not {a[0] for a in after['addresses']} & {'192.0.2.10', '2001:db8:10::10'}
    assert after['routes'] == before['routes'] == []
    assert not report['verification']['satisfied'] and report['verification']['remaining']['steps']
    print(json.dumps(after, indent=2))
    print('Desired state remains unmet; the original error is retained.')
    print('Recovery is best-effort for managed fields, not an atomic transaction.')


if __name__ == '__main__':
    main()
