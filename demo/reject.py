"""Malformed schema is rejected during file preflight, before socket creation."""

from reconcile import BINARY, ROOT, command

result = command(str(BINARY), 'plan', str(ROOT / 'demo/invalid-desired.json'), '--json', success=False)
assert not result.stdout
assert 'InvalidField' in result.stderr and 'unknown field' in result.stderr
print('Malformed desired fixture: InvalidField (unknown field); nonzero CLI exit; no plan emitted.')
