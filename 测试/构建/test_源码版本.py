"""测试边界：核验混合上传、旧源码遗漏和换行规范化。
输入：隔离临时源码目录；输出：交付清单匹配/拒绝断言。
"""
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch
from 临时工作区 import TemporaryWorkspace

spec = importlib.util.spec_from_file_location('source_verification', Path(__file__).resolve().parents[2] / '构建/检查源码版本.py')
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)


class SourceVersionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = TemporaryWorkspace()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for directory in ('应用', '测试', '资源', '构建'):
            (self.root / directory).mkdir()
        (self.root / 'project.yml').write_text('MARKETING_VERSION: "0.3.0"\nCURRENT_PROJECT_VERSION: "2"\n')
        (self.root / 'Package.swift').write_text('// package\n')
        (self.root / 'codemagic.yaml').write_text('workflows: {}\n')
        (self.root / '应用/事项.swift').write_text('// source\n')
        manifest = {'version': '0.3.0', 'build': '2', 'files': source.source_files(self.root)}
        (self.root / source.MANIFEST).write_text(json.dumps(manifest))

    def test_complete_upload_matches(self):
        self.assertEqual(source.verify(self.root)['version'], '0.3.0')

    def test_fingerprint_and_ci_commit_are_reported(self):
        with patch.dict(source.os.environ, {'CM_COMMIT': 'a' * 40}):
            result = source.verify(self.root)
        self.assertEqual(result['commit'], 'a' * 40)
        self.assertEqual(result['manifestSHA256'], source.digest(self.root / source.MANIFEST))

    def test_old_file_replacement_fails_with_changed_path(self):
        (self.root / '应用/事项.swift').write_text('// old implementation\n')
        with self.assertRaisesRegex(RuntimeError, 'changed:.*事项.swift'):
            source.verify(self.root)

    def test_missing_new_feature_file_is_rejected(self):
        (self.root / '应用/事项.swift').unlink()
        with self.assertRaisesRegex(RuntimeError, 'Missing:.*事项.swift'):
            source.verify(self.root)

    def test_extra_stale_source_file_is_rejected(self):
        (self.root / '应用/过期.swift').write_text('// stale\n')
        with self.assertRaisesRegex(RuntimeError, 'extra:.*过期.swift'):
            source.verify(self.root)

    def test_windows_bom_and_crlf_are_normalized(self):
        (self.root / '应用/事项.swift').write_bytes(b'\xef\xbb\xbf// source\r\n')
        self.assertEqual(source.verify(self.root)['version'], '0.3.0')


if __name__ == '__main__':
    unittest.main()
