"""测试边界：模拟 SDK/运行时与启动超时，验证专用设备重试不掩盖失败。
输入：固定 simctl 结果；输出：命令顺序与就绪断言，不启动真实模拟器。
"""
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch
from 临时工作区 import TemporaryWorkspace

spec = importlib.util.spec_from_file_location('ci_simulator', Path(__file__).resolve().parents[2] / '构建/模拟器准备.py')
simulator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(simulator)


def runtime(version, available=True):
    return {'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-' + version.replace('.', '-'),
            'version': version, 'isAvailable': available}


class SimulatorPreparationTests(unittest.TestCase):
    def test_runtime_matches_sdk_instead_of_first_or_newer_device(self):
        values = [runtime('26.1'), runtime('25.0'), runtime('26.0')]
        self.assertEqual(simulator.matching_runtime(values, '26.0')['version'], '26.0')

    def test_unavailable_or_mismatched_runtime_is_explicit_failure(self):
        with self.assertRaisesRegex(RuntimeError, 'matching simulator SDK'):
            simulator.matching_runtime([runtime('26.0', False), runtime('26.1')], '26.0')

    def test_fresh_device_uses_selected_runtime_and_persists_selection(self):
        identifier = '00000000-0000-0000-0000-000000000001'

        def fake(arguments, timeout=30):
            if '--show-sdk-version' in arguments:
                return '26.0'
            if 'runtimes' in arguments:
                return json.dumps({'runtimes': [runtime('26.1'), runtime('26.0')]})
            self.assertEqual(arguments[-1], runtime('26.0')['identifier'])
            self.assertTrue(arguments[3].startswith('OhRight-CI-'))
            return identifier

        with TemporaryWorkspace() as directory, patch.object(simulator, 'command', side_effect=fake), patch.object(simulator, 'open_simulator'):
            root = Path(directory)
            self.assertEqual(simulator.create_device(root), identifier)
            self.assertEqual((root / 'simulator-id.txt').read_text().strip(), identifier)
            self.assertEqual(json.loads((root / 'simulator-selection.json').read_text())['sdk'], '26.0')

    def boot(self, failures):
        temporary = TemporaryWorkspace()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        identifier = 'dedicated-device'
        (root / 'simulator-selection.json').write_text(json.dumps({'udid': identifier, 'deviceName': 'OhRight-CI-test'}))
        commands = []
        boots = 0

        def fake(arguments, timeout=30):
            nonlocal boots
            commands.append(arguments)
            if 'bootstatus' in arguments:
                boots += 1
                if boots <= failures:
                    raise subprocess.TimeoutExpired(arguments, timeout, output='Waiting on BackBoard')
                return 'Finished booting'
            return '{}'

        return root, identifier, commands, fake

    def test_one_timeout_restarts_only_dedicated_device_and_requires_success(self):
        root, identifier, commands, fake = self.boot(1)
        with patch.object(simulator, 'command', side_effect=fake), patch.dict(simulator.os.environ, {'DEVELOPER_DIR': '/Xcode/Developer'}):
            simulator.boot_device(root, identifier)
        self.assertEqual([c for c in commands if 'shutdown' in c], [['xcrun', 'simctl', 'shutdown', identifier]])
        self.assertEqual(len([c for c in commands if 'bootstatus' in c]), 2)
        result = json.loads((root / 'simulator-boot-result.json').read_text())
        self.assertEqual([value['ready'] for value in result], [False, True])
        self.assertFalse(any('erase' in c or 'delete' in c or 'all' in c for c in commands))

    def test_two_timeouts_fail_instead_of_skipping_readiness(self):
        root, identifier, commands, fake = self.boot(2)
        with patch.object(simulator, 'command', side_effect=fake), patch.dict(simulator.os.environ, {'DEVELOPER_DIR': '/Xcode/Developer'}):
            with self.assertRaisesRegex(RuntimeError, 'failed readiness checks twice'):
                simulator.boot_device(root, identifier)
        self.assertEqual(len([c for c in commands if 'bootstatus' in c]), 2)
        self.assertFalse(any(value['ready'] for value in json.loads((root / 'simulator-boot-result.json').read_text())))

    def test_foreign_device_is_never_restarted(self):
        root, _, _, fake = self.boot(0)
        with patch.object(simulator, 'command', side_effect=fake) as command:
            with self.assertRaisesRegex(RuntimeError, 'not created by this build'):
                simulator.boot_device(root, 'another-device')
        command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
