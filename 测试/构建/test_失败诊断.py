"""测试边界：实际日志文件验证首错、断言加超时、旧日志排除和诊断容错。
输入：隔离目录中的阶段日志及文件复制替身；输出：摘要/原退出码断言。
"""
import contextlib
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch
from 临时工作区 import TemporaryWorkspace


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parents[2] / '构建' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


summary = load('failure_summary', '失败摘要.py')
crashes = load('crash_collection', '收集崩溃报告.py')


class FailureDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.workspace = TemporaryWorkspace()
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        self.inventory = self.root / 'verification-current-logs.txt'
        self.inventory.write_text('ios-ui-tests.log\n', encoding='utf-8')

    def log(self, name, content):
        (self.root / name).write_text(content, encoding='utf-8')

    def test_assertion_is_primary_even_when_wrapper_later_times_out(self):
        self.log('ios-ui-tests.log', '=== 5/5 UI tests: START (limit 300s) ===\n'
                 'Settings.swift:77: error: XCTAssertNotEqual failed: 0 equals 0\n'
                 "Test Case '-[ExampleUITests testExample]' failed (75 seconds).\n"
                 '=== 5/5 UI tests: TIMEOUT after 300s ===\n')
        result = summary.summarize(self.root, 124)
        self.assertEqual(result['exitCode'], 124)
        self.assertEqual(result['primaryFailure'], 'assertion_failure')
        self.assertEqual(result['termination'], 'timeout')
        self.assertEqual(result['firstError']['line'], 2)
        self.assertEqual(result['stages'][0]['status'], 'timeout')

    def test_first_error_survives_hundreds_of_following_errors(self):
        self.log('ios-ui-tests.log', 'first.swift:1: error: first assertion\n' + 'later: error: secondary\n' * 200)
        result = summary.summarize(self.root, 65)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            summary.render(result)
        self.assertIn('first.swift:1', output.getvalue())
        self.assertLess(len(output.getvalue().splitlines()), 20)

    def test_unregistered_stale_ui_log_is_ignored(self):
        self.inventory.write_text('core-tests.log\n', encoding='utf-8')
        self.log('core-tests.log', '=== Core: START (limit 300s) ===\n=== Core: TIMEOUT after 300s ===\n')
        self.log('ios-ui-tests.log', 'old.swift:1: error: XCTAssertTrue failed\n')
        result = summary.summarize(self.root, 124)
        self.assertIsNone(result['firstError'])
        self.assertEqual(result['primaryFailure'], 'infrastructure_timeout')

    def test_recovered_error_in_passed_stage_does_not_hide_ui_failure(self):
        self.inventory.write_text('ios-unit-tests.log\nios-ui-tests.log\n', encoding='utf-8')
        self.log('ios-unit-tests.log', 'error: recovered storage diagnostic\n=== Units: PASS (exit 0) ===\n')
        self.log('ios-ui-tests.log', 'Settings.swift:1: error: XCTAssertEqual failed\n')
        self.assertEqual(summary.summarize(self.root, 65)['firstError']['log'], 'ios-ui-tests.log')

    def test_success_keeps_stage_elapsed_and_full_mode(self):
        self.log('ios-ui-tests.log', '=== UI: PASS (exit 0) ===\n=== Stage elapsed: 25.123s ===\n')
        result = summary.summarize(self.root, 0)
        self.assertEqual(result['primaryFailure'], 'passed')
        self.assertEqual(result['mode'], 'full')
        self.assertEqual(result['stages'][0]['elapsedSeconds'], 25.123)
        self.assertEqual(summary.summarize(self.root, 0)['primaryFailure'], 'passed')

    def test_log_path_outside_build_is_refused(self):
        self.inventory.write_text('../private.log\n', encoding='utf-8')
        result = summary.summarize(self.root, 1)
        self.assertEqual(result['stages'], [])
        self.assertIn('Refused', result['diagnosticErrors'][0])

    def test_crash_copy_error_does_not_abort_remaining_reports(self):
        source = self.root / 'reports'
        source.mkdir()
        (source / 'first.ips').write_text('first')
        (source / 'second.ips').write_text('second')
        with patch.object(crashes.shutil, 'copy2', side_effect=[PermissionError('unreadable'), None]) as copy:
            with contextlib.redirect_stdout(io.StringIO()):
                crashes.collect(source, self.root / 'collected')
        self.assertEqual(copy.call_count, 2)


if __name__ == '__main__':
    unittest.main()
