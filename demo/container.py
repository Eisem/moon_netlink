"""Initialize and remove disposable network resources through the public SDK."""

import json
import os

from reconcile import ROOT, cli, configuration, run


def main():
    parent = os.environ.get('MOONNETLINK_DEMO_PARENT_NETNS')
    assert parent and os.readlink('/proc/self/ns/net') != parent, 'use bash demo/container.sh'
    example = str(ROOT / '_build/native/debug/build/examples/configure_veth/configure_veth.exe')
    print('1. Public RouteClient API: configure MTU, UP, IPv4/IPv6 addresses and routes.')
    configured = False
    try:
        print(run(example, 'testveth', 'add', '--yes'), end='')
        configured = True
        actual = configuration()
        assert actual['mtu'] == 1400 and actual['up']
        assert {'192.0.2.10', '2001:db8::10'} <= {a[0] for a in actual['addresses']}
        print('\n2. Public typed queries and independent ip -j comparison.')
        for kind in ('link', 'address', 'route'):
            rows = json.loads(cli(kind, 'show', '--json'))
            selected = [r for r in rows if (kind == 'link' and r.get('name') == 'testveth')
                        or (kind == 'address' and r.get('address') in ('192.0.2.10', '2001:db8::10'))
                        or (kind == 'route' and r.get('table') == 1000)]
            assert selected, (kind, rows)
            print(f'{kind}: {len(selected)} managed typed objects')
        print(json.dumps(actual, indent=2))
        print(run('python3', '.ci/diff_ip_json.py'), end='')
    finally:
        if configured:
            print('\n3. Public API deletion and Link DOWN.')
            print(run(example, 'testveth', 'delete', '--yes'), end='')
    actual = configuration()
    assert actual['mtu'] == 1500 and not actual['up'] and not actual['routes']
    assert not {'192.0.2.10', '2001:db8::10'} & {a[0] for a in actual['addresses']}
    print('Query verified: managed addresses/routes absent, MTU=1500, UP=false.')


if __name__ == '__main__':
    main()
