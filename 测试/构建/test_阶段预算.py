"""测试边界：执行验证脚本中的真实 Python 阶段包装，检查全局预算与退出状态。
输入：独立子进程和已过期截止时间；输出：成功/失败原码、过期时不启动命令。
Windows 不模拟 POSIX 进程组终止，真实超时清理仍需 macOS 验证。
"""
import os
from pathlib import Path
import subprocess
import sys
import time
import unittest


SCRIPT = (Path(__file__).resolve().parents[2] / '构建/验证工程.sh').read_text(encoding='utf-8-sig')
WRAPPER = SCRIPT.split('  python3 - "$@" <<\'PY\'\n', 1)[1].split('\nPY\n', 1)[0]


class StageBudgetTests(unittest.TestCase):
    def run_stage(self, statement, deadline):
        environment = dict(os.environ, OHRIGHT_VERIFY_DEADLINE=str(deadline))
        return subprocess.run([sys.executable, '-c', WRAPPER, '10', 'Probe', sys.executable, '-c', statement],
                              env=environment, text=True, capture_output=True, timeout=15)

    def test_success_and_elapsed_are_reported(self):
        result = self.run_stage('pass', time.time() + 60)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('PASS (exit 0)', result.stdout)
        self.assertIn('Stage elapsed:', result.stdout)

    def test_command_failure_keeps_original_exit_code(self):
        result = self.run_stage('raise SystemExit(7)', time.time() + 60)
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertIn('FAIL (exit 7)', result.stdout)

    def test_global_deadline_prevents_starting_next_stage(self):
        result = self.run_stage('print("SHOULD_NOT_START")', time.time() - 1)
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertIn('global deadline reached', result.stdout)
        self.assertNotIn('SHOULD_NOT_START', result.stdout)


if __name__ == '__main__':
    unittest.main()
