"""Run each named fault regression; an empty or skipped selection is a failure."""
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
for filename, name in json.loads((root / '.ci/critical-tests.json').read_text()):
    result = subprocess.run(['moon', 'test', '--target', 'native', filename, '--filter', name],
                            cwd=root, text=True, capture_output=True, timeout=120)
    output = result.stdout + result.stderr
    print(name, flush=True)
    counts = re.search(r'Total tests: (\d+), passed: (\d+), failed: (\d+)', output)
    if result.returncode or not counts or counts.groups() != ('1', '1', '0'):
        raise SystemExit('Critical test did not run exactly once and pass:\n' + output)
