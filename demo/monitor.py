"""Listen before changing configuration; validate typed events and filtering."""

import json
import os
import pathlib
import queue
import signal
import subprocess
import tempfile
import threading
import time

from reconcile import BINARY, DESIRED, cli


class Watch:
    def __init__(self, kind):
        self.kind = kind
        self.output, self.errors = queue.Queue(), queue.Queue()
        self.process = subprocess.Popen([str(BINARY), 'watch', kind, '--jsonl'],
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        text=True, start_new_session=True)
        self.readers = []
        for pipe, target in ((self.process.stdout, self.output), (self.process.stderr, self.errors)):
            reader = threading.Thread(target=self.feed, args=(pipe, target), daemon=True)
            reader.start()
            self.readers.append(reader)

    @staticmethod
    def feed(pipe, target):
        for line in pipe:
            target.put(line)

    def ready(self):
        deadline = time.monotonic() + 15
        diagnostics = []
        while time.monotonic() < deadline:
            try:
                line = self.errors.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            diagnostics.append(line)
            if line.strip() == 'moonnet watch: ready':
                print(f'watch {self.kind}: subscribed before mutations')
                return
        raise RuntimeError('monitor failed to subscribe: ' + ''.join(diagnostics))

    def collect(self, predicate):
        rows = []
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            try:
                line = self.output.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            event = json.loads(line)
            assert set(event) == {'event', 'object'}, event
            rows.append(event)
            if predicate(rows):
                return rows
        diagnostics = []
        while not self.errors.empty():
            diagnostics.append(self.errors.get_nowait())
        raise RuntimeError('missing events; discard cached state and query a fresh snapshot\n'
                           + ''.join(diagnostics))

    def stop(self):
        try:
            os.killpg(self.process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(self.process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.process.wait(timeout=5)
        for reader in self.readers:
            reader.join(timeout=5)
            assert not reader.is_alive(), 'monitor reader still running'
        self.process.stdout.close()
        self.process.stderr.close()
        assert self.process.poll() is not None


def expected(rows):
    events = {r['event'] for r in rows}
    return {'link.changed', 'address.added', 'address.deleted', 'route.added', 'route.deleted'} <= events \
        and route_events(rows) and all(
            any(r['event'] == kind and r['object'].get('address') == address for r in rows)
            for kind in ('address.added', 'address.deleted')
            for address in ('192.0.2.10', '2001:db8:10::10'))


def route_events(rows):
    return all(any(r['event'] == kind and r['object'].get('family') == family
                   and r['object'].get('table') == 1000 for r in rows)
               for kind in ('route.added', 'route.deleted') for family in ('ipv4', 'ipv6'))


def main():
    parent = os.environ.get('MOONNETLINK_DEMO_PARENT_NETNS')
    assert parent and os.readlink('/proc/self/ns/net') != parent, 'use bash demo/monitor.sh'
    watchers = []
    try:
        for kind in ('all', 'route'):
            watcher = Watch(kind)
            watchers.append(watcher)
            watcher.ready()
        added = json.loads(cli('apply', str(DESIRED), '--yes', '--json'))
        assert added['succeeded'], added
        desired = json.loads(DESIRED.read_text(encoding='utf-8'))
        for kind in ('addresses', 'routes'):
            for intent in desired[kind]:
                intent['ensure'] = 'absent'
        desired['links'][0].update(up=False, mtu=1500)
        with tempfile.TemporaryDirectory(prefix='moonnet-demo-monitor-') as directory:
            path = pathlib.Path(directory) / 'absent.json'
            path.write_text(json.dumps(desired), encoding='utf-8')
            removed = json.loads(cli('apply', str(path), '--yes', '--json'))
            assert removed['succeeded'], removed
        events = watchers[0].collect(expected)
        routes = watchers[1].collect(route_events)
        assert all(r['event'].startswith('route.') for r in routes)
        print('\nTyped event projections from the actual JSONL stream:')
        displayed = set()
        for row in events:
            if row['event'].startswith('route.') and row['object'].get('table') != 1000:
                continue
            if row['event'].startswith('address.') and row['object'].get('address') not in (
                    '192.0.2.10', '2001:db8:10::10'):
                continue
            identity = row['event'], row['object'].get('family')
            if identity in displayed:
                continue
            displayed.add(identity)
            projection = {key: value for key, value in row['object'].items()
                          if key in ('name', 'index', 'mtu', 'family', 'local', 'address', 'destination', 'table')}
            print(json.dumps({'event': row['event'], 'object': projection}))
        print(f'Route-only filter: {len(routes)} route events; no Link/Address events.')
        print('On EventStreamLost: discard cached state, query a fresh snapshot, then subscribe again.')
        print('Event loss is not intentionally triggered by this live demo; overrun rejection has a decoder test.')
    finally:
        cleanup_errors = []
        for watcher in reversed(watchers):
            try:
                watcher.stop()
            except Exception as error:
                cleanup_errors.append(str(error))
        if cleanup_errors:
            raise RuntimeError('monitor cleanup failed: ' + '; '.join(cleanup_errors))


if __name__ == '__main__':
    main()
