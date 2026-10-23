import tempfile
import unittest
from pathlib import Path

from coverage_gate import PACKAGES, collect, compare


class CoverageGateTests(unittest.TestCase):
    def test_regression_and_deleted_coverage_fail(self):
        baseline = {p: dict(covered=8, total=10) for p in PACKAGES}
        current = {p: dict(covered=8, total=10) for p in PACKAGES}
        self.assertEqual(compare(current, baseline), [])
        current['core'] = dict(covered=8, total=11)
        self.assertTrue(compare(current, baseline))
        current['core'] = dict(covered=7, total=8)
        self.assertTrue(compare(current, baseline))

    def test_missing_package_and_duplicate_file_fail(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent.parent / '_build') as directory:
            report = Path(directory) / 'report.xml'
            report.write_text('<coverage/>')
            with self.assertRaisesRegex(ValueError, 'missing instrumentation'):
                collect(report)
            report.write_text('<coverage><class filename="core/a.mbt"/>'
                              '<class filename="core/a.mbt"/></coverage>')
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                collect(report)


if __name__ == '__main__':
    unittest.main()
