"""Fetch content-addressed official archives, or reuse verified offline copies."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def fetch(archive, cache):
    path = cache / (archive['name'] + '-' + archive['sha256'] + '.tar.gz')
    if not path.exists():
        partial = path.with_suffix('.partial')
        try:
            subprocess.run(['curl', '--retry', '3', '-fsSL', archive['url'], '-o', str(partial)], check=True)
            if digest(partial) != archive['sha256']:
                raise ValueError('Upstream archive changed; restore a locked cache or review a toolchain update')
            partial.replace(path)
        finally:
            partial.unlink(missing_ok=True)
    if digest(path) != archive['sha256']:
        raise ValueError(f'Corrupt cached archive: {path}')
    return path


if __name__ == '__main__':
    cache = Path(sys.argv[1]).expanduser().resolve()
    cache.mkdir(parents=True, exist_ok=True)
    lock = json.loads(Path(__file__).with_name('toolchain-lock.json').read_text())
    for archive in lock['archives']:
        print(fetch(archive, cache))
