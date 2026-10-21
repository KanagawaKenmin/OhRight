"""测试边界：在项目 build 中创建隔离目录，清理前验证路径仍在专用父目录内。
避开 Windows 沙箱中 tempfile 的 0700 ACL 兼容问题；不改变被测试逻辑。
"""
from pathlib import Path
import shutil
import uuid


class TemporaryWorkspace:
    def __init__(self):
        self.base = Path(__file__).resolve().parents[2] / 'build/build-script-test-data'
        self.base.mkdir(parents=True, exist_ok=True)
        self.root = self.base / uuid.uuid4().hex
        self.root.mkdir()
        self.name = str(self.root)

    def cleanup(self):
        if self.root.resolve().parent != self.base.resolve():
            raise RuntimeError('Refusing cleanup outside the isolated test directory')
        if self.root.exists():
            shutil.rmtree(self.root)

    def __enter__(self):
        return self.name

    def __exit__(self, *_):
        self.cleanup()
