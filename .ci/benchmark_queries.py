"""End-to-end CLI Link query benchmark, restricted to a disposable namespace."""
import argparse
import json
import math
import os
from pathlib import Path
import platform
import statistics
import subprocess
import time


def summarize(samples):
    ordered = sorted(samples)
    return dict(min_ns=min(samples), median_ns=statistics.median(samples),
                mean_ns=statistics.mean(samples), p95_ns=ordered[math.ceil(len(samples) * .95) - 1],
                max_ns=max(samples))


def normalize(rows, source):
    result = []
    for row in rows:
        if source == 'moonnet':
            result.append((row['index'], row['name'], row['mtu'], bool(row['flags'] & 1)))
        else:
            result.append((row['ifindex'], row['ifname'], row['mtu'], 'UP' in row['flags']))
    if len({row[0] for row in result}) != len(result):
        raise ValueError('duplicate interface index')
    return sorted(result)


def command(args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=30)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--interfaces', type=int, default=32)
    parser.add_argument('--samples', type=int, default=30)
    parser.add_argument('--warmup', type=int, default=5)
    parser.add_argument('--output', type=Path, default=Path('_build/benchmarks/queries.json'))
    args = parser.parse_args()
    if not (1 <= args.interfaces <= 1000 and 2 <= args.samples <= 1000 and 1 <= args.warmup <= 100):
        parser.error('interfaces: 1..1000; samples: 2..1000; warmup: 1..100')
    parent = os.environ.get('MOONNETLINK_BENCH_PARENT_NETNS')
    if not parent or os.readlink('/proc/self/ns/net') == parent:
        raise SystemExit('benchmark requires the isolated namespace wrapper')
    args.output.unlink(missing_ok=True)
    command(['ip', 'link', 'set', 'lo', 'up'])
    for index in range(args.interfaces):
        command(['ip', 'link', 'add', f'mnlbench{index}', 'type', 'dummy'])
    commands = {
        'moonnet': [str(Path('_build/native/release/build/cmd/moonnet/moonnet.exe').resolve()), 'link', 'show', '--json'],
        'ip': ['ip', '-j', 'link', 'show'],
    }
    reference = normalize(json.loads(command(commands['ip']).stdout), 'ip')
    assert len(reference) == args.interfaces + 1, reference
    raw = {name: [] for name in commands}
    sizes = {name: [] for name in commands}
    for iteration in range(args.warmup + args.samples):
        # Alternate which process runs first to reduce systematic ordering bias.
        order = ('moonnet', 'ip') if iteration % 2 == 0 else ('ip', 'moonnet')
        for name in order:
            started = time.perf_counter_ns()
            output = command(commands[name]).stdout
            rows = json.loads(output)
            elapsed = time.perf_counter_ns() - started
            if normalize(rows, name) != reference:
                raise RuntimeError(f'{name}: observation changed; discard this run')
            if iteration >= args.warmup:
                raw[name].append(elapsed)
                sizes[name].append(len(output.encode('utf-8')))
    report = dict(schema_version=1, scope='process-start + kernel-query + JSON-output + Python-JSON-parse',
                  fields=['index', 'name', 'mtu', 'administratively_up'],
                  interfaces=args.interfaces, objects=len(reference), warmup=args.warmup,
                  samples=args.samples, order='alternating',
                  environment=dict(kernel=platform.release(), machine=platform.machine(),
                                   python=platform.python_version(),
                                   cpu_model=next((line.split(':', 1)[1].strip()
                                                   for line in Path('/proc/cpuinfo').read_text().splitlines()
                                                   if line.startswith('model name')), 'unknown'),
                                   logical_cpus=os.cpu_count(),
                                   toolchain=command(['moon', 'version', '--all']).stdout,
                                   iproute2=command(['ip', '-Version']).stdout,
                                   commit=command(['git', 'rev-parse', 'HEAD']).stdout.strip()),
                  commands=commands, raw_ns=raw, output_bytes=sizes,
                  statistics={name: summarize(values) for name, values in raw.items()})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report['statistics'], indent=2))


if __name__ == '__main__':
    main()
