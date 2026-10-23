"""Compare compiler-instrumented line coverage with reviewed package baselines."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

PACKAGES = ('core', 'route', 'state', 'transport', 'reconcile')


def collect(path):
    files = {}
    for item in ET.parse(path).findall('.//class'):
        name = item.attrib['filename'].replace('\\', '/')
        if name.split('/')[0] not in PACKAGES:
            continue
        if name in files:
            raise ValueError(f'duplicate source file: {name}')
        lines = {}
        for line in item.findall('./lines/line'):
            number, hits = int(line.attrib['number']), int(line.attrib['hits'])
            if number <= 0 or hits < 0 or number in lines:
                raise ValueError(f'invalid coverage counter: {name}:{number}')
            lines[number] = hits
        files[name] = lines
    result = {}
    for package in PACKAGES:
        counters = [hit for name, lines in files.items()
                    if name.startswith(package + '/') for hit in lines.values()]
        if not counters:
            raise ValueError(f'missing instrumentation: {package}')
        result[package] = dict(covered=sum(hit > 0 for hit in counters), total=len(counters))
    return result


def compare(current, baseline):
    errors = []
    if set(baseline) != set(PACKAGES):
        raise ValueError('baseline must include all five library packages')
    for package in PACKAGES:
        now, before = current[package], baseline[package]
        if not 0 < before['covered'] <= before['total']:
            raise ValueError(f'invalid baseline: {package}')
        if now['covered'] * before['total'] < before['covered'] * now['total']:
            errors.append(f'{package}: line coverage ratio regressed')
        if now['covered'] < before['covered']:
            errors.append(f'{package}: covered line count regressed; review removed code/tests')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('--baseline', type=Path, default=Path('.ci/coverage-baseline.json'))
    parser.add_argument('--write-baseline', action='store_true')
    args = parser.parse_args()
    result = collect(args.report)
    for name, row in result.items():
        print(f"{name}: {row['covered']}/{row['total']} ({row['covered']/row['total']:.2%})")
    if args.write_baseline:
        args.baseline.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    else:
        errors = compare(result, json.loads(args.baseline.read_text(encoding='utf-8')))
        if errors:
            raise SystemExit('\n'.join(errors))


if __name__ == '__main__':
    main()
