"""测试边界：验证运行时冷启动预热、查询超时重试及失败不越过。
输入：真实隔离目录和系统命令替身；输出：实际命令顺序/时间预算/诊断断言。
"""
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch
from 临时工作区 import TemporaryWorkspace

spec = importlib.util.spec_from_file_location('runtime_discovery', Path(__file__).resolve().parents[2] / '构建/模拟器准备.py')
simulator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(simulator)


class RuntimeDiscoveryTests(unittest.TestCase):
    def test_opens_selected_xcode_simulator_before_query(self):
        commands = []

        def fake(arguments, timeout=30):
            commands.append((arguments, timeout))
            return json.dumps({'runtimes': []}) if 'runtimes' in arguments else ''

        with TemporaryWorkspace() as directory, patch.object(simulator, 'command', side_effect=fake), \
                patch.dict(simulator.os.environ, {'DEVELOPER_DIR': '/SelectedXcode/Developer'}):
            self.assertEqual(simulator.runtime_list(Path(directory)), {'runtimes': []})
        self.assertEqual(commands[0][0], ['open', '-a', str(Path('/SelectedXcode/Developer/Applications/Simulator.app'))])
        self.assertEqual(commands[1], (['xcrun', 'simctl', 'list', 'runtimes', '--json'], 90))

    def test_cold_query_timeout_retries_and_preserves_first_failure(self):
        count = 0

        def fake(arguments, timeout=30):
            nonlocal count
            if 'runtimes' in arguments:
                count += 1
                if count == 1:
                    raise subprocess.TimeoutExpired(arguments, timeout)
                return json.dumps({'runtimes': [{'identifier': 'available'}]})
            return 'CoreSimulatorService'

        with TemporaryWorkspace() as directory, patch.object(simulator, 'command', side_effect=fake), \
                patch.object(simulator, 'open_simulator') as warmup:
            root = Path(directory)
            self.assertEqual(simulator.runtime_list(root)['runtimes'], [{'identifier': 'available'}])
            self.assertEqual(warmup.call_count, 2)
            self.assertEqual([row['ready'] for row in json.loads((root / 'simulator-discovery-result.json').read_text())], [False, True])
            self.assertTrue((root / 'simulator-discovery-attempt-1.txt').exists())

    def test_two_query_timeouts_fail_without_creating_device(self):
        commands = []

        def fake(arguments, timeout=30):
            commands.append(arguments)
            if '--show-sdk-version' in arguments:
                return '26.0'
            if 'runtimes' in arguments:
                raise subprocess.TimeoutExpired(arguments, timeout)
            return 'host diagnostic'

        with TemporaryWorkspace() as directory, patch.object(simulator, 'command', side_effect=fake), patch.object(simulator, 'open_simulator'):
            root = Path(directory)
            with self.assertRaisesRegex(RuntimeError, 'runtime discovery failed twice'):
                simulator.create_device(root)
            self.assertFalse((root / 'simulator-id.txt').exists())
            self.assertEqual(len(json.loads((root / 'simulator-discovery-result.json').read_text())), 2)
        self.assertFalse(any('create' in command or 'erase' in command or 'killall' in command for command in commands))

    def test_invalid_runtime_json_is_not_retried_or_accepted(self):
        with TemporaryWorkspace() as directory, patch.object(simulator, 'command', return_value='not-json') as command, \
                patch.object(simulator, 'open_simulator'):
            with self.assertRaises(ValueError):
                simulator.runtime_list(Path(directory))
        self.assertEqual(command.call_count, 1)

    def test_unavailable_ui_does_not_replace_required_runtime_query(self):
        with TemporaryWorkspace() as directory, patch.object(simulator, 'command', return_value='{"runtimes": []}') as command, \
                patch.object(simulator, 'open_simulator', side_effect=OSError('UI unavailable')):
            self.assertEqual(simulator.runtime_list(Path(directory)), {'runtimes': []})
        command.assert_called_once_with(['xcrun', 'simctl', 'list', 'runtimes', '--json'], timeout=90)


if __name__ == '__main__':
    unittest.main()
