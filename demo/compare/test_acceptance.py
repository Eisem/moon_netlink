"""Regression tests for fail-closed comparison acceptance (no kernel writes)."""
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import compare_results
import run_cases


class AcceptanceTests(unittest.TestCase):
    def results(self):
        cases = [json.loads((compare_results.HERE / name).read_text(encoding='utf8'))
                 for name in json.loads((compare_results.HERE / 'contract.json').read_text(encoding='utf8'))['cases']]
        results = {}
        for side, extras in compare_results.EXTRA_CHECKS.items():
            entries = []
            for case in cases:
                expected = case['expected']
                observed = ({'rejection': expected['rejection'], 'attempted_writes': 0,
                             'preserved': [], 'state_unchanged': True}
                            if case['kind'] == 'reject' else
                            {'plan': [], 'completed': [], 'failed_index': None, 'not_executed': [],
                             'attempted_writes': 0, 'compensations': [], 'verification_satisfied': True,
                             'satisfied': [], 'preserved': []})
                entries.append({'id': case['id'], 'status': 'ok', 'problems': [], 'observed': observed})
            entries.extend({'id': name, 'status': 'ok', 'problems': []} for name in extras)
            results[side] = {'side': side, 'selected': [case['id'] for case in cases],
                             'status': 'ok', 'problems': [], 'cases': entries}
        return results

    def report(self, results, *args):
        with tempfile.TemporaryDirectory() as workspace:
            for side, result in results.items():
                (Path(workspace) / f'{side}.json').write_text(json.dumps(result), encoding='utf8')
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                return compare_results.main(['compare', '--results', workspace, '--json', *args])

    def test_valid_results_and_side_specific_checks(self):
        self.assertEqual(self.report(self.results()), 0)

    def test_empty_results_fail(self):
        results = self.results()
        for result in results.values():
            result['cases'] = []
        self.assertEqual(self.report(results), 1)

    def test_missing_shared_or_extra_case_fails(self):
        for index in (0, -1):
            results = self.results()
            results['app']['cases'].pop(index)
            self.assertEqual(self.report(results), 1)

    def test_failed_case_or_top_level_status_without_problems_fails(self):
        for top_level in (False, True):
            results = self.results()
            target = results['app'] if top_level else results['app']['cases'][0]
            target['status'] = 'failed'
            self.assertEqual(self.report(results), 1)

    def test_duplicate_case_fails(self):
        results = self.results()
        results['script']['cases'].append(copy.deepcopy(results['script']['cases'][0]))
        self.assertEqual(self.report(results), 1)

    def test_missing_required_observation_fails_even_on_both_sides(self):
        for field in compare_results.COMPARED_FIELDS:
            results = self.results()
            for result in results.values():
                del result['cases'][0]['observed'][field]
            with self.subTest(field=field):
                self.assertEqual(self.report(results), 1)

    def test_invalid_observation_fails(self):
        results = self.results()
        results['app']['cases'][0]['observed'] = None
        self.assertEqual(self.report(results), 1)

    def test_invalid_field_types_fail_even_when_both_sides_agree(self):
        for field in compare_results.COMPARED_FIELDS:
            results = self.results()
            for result in results.values():
                result['cases'][0]['observed'][field] = 'invalid'
            with self.subTest(field=field):
                self.assertEqual(self.report(results), 1)

    def test_mismatching_observations_fail(self):
        results = self.results()
        results['app']['cases'][0]['observed']['attempted_writes'] = 100
        self.assertEqual(self.report(results), 1)

    def test_selected_subset_matches_requested_cases_in_contract_order(self):
        results = self.results()
        for side, result in results.items():
            result['selected'] = ['converge', 'repeat']
            result['cases'] = [entry for entry in result['cases']
                               if entry['id'] in result['selected'] or entry['id'] in compare_results.EXTRA_CHECKS[side]]
        self.assertEqual(self.report(results, '--case', 'repeat', '--case', 'converge'), 0)
        self.assertEqual(self.report(results), 1)

    def test_invalid_sides_fail(self):
        for sides in ('', 'script,script', 'other'):
            with self.assertRaises(SystemExit) as error:
                self.report({}, '--sides', sides)
            self.assertEqual(error.exception.code, 2)

    def test_namespace_failure_stops_before_side_construction(self):
        for env in ({}, {'MOONNETLINK_DEMO_PARENT_NETNS': 'same'}):
            with patch.dict(os.environ, env, clear=True), patch.object(run_cases.os, 'readlink', return_value='same'), \
                    patch.dict(run_cases.SIDES, {'script': unittest.mock.Mock(side_effect=AssertionError('must not execute'))}), \
                    contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(run_cases.main(['run_cases', '--case', 'repeat']), 3)

    def test_unknown_and_empty_selection_stop_before_execution(self):
        for arguments in (['--case', 'no-such-case'], ['--exclude', 'no-such-case'],
                          ['--case', 'repeat', '--exclude', 'repeat']):
            with patch.dict(os.environ, {'MOONNETLINK_DEMO_PARENT_NETNS': 'parent'}), \
                    patch.object(run_cases.os, 'readlink', return_value='isolated'), \
                    patch.dict(run_cases.SIDES, {'script': unittest.mock.Mock(side_effect=AssertionError('must not execute'))}), \
                    contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    run_cases.main(['run_cases', *arguments])
                self.assertEqual(error.exception.code, 2)

    def test_no_inferred_writes_or_unverifiable_audit(self):
        side = run_cases.Side()
        invocation = subprocess.CompletedProcess([], 0, stdout='{"completed":[],"failed":null}', stderr='')
        self.assertIsNone(side.attempted_writes(invocation))
        self.assertIsNone(side.total_write_attempts(invocation))
        invocation.stderr = 'moonnetlink-mutation-attempts:0\n'
        self.assertEqual(side.total_write_attempts(invocation), 0)
        invocation.stderr *= 2
        self.assertIsNone(side.total_write_attempts(invocation))


if __name__ == '__main__':
    unittest.main()
