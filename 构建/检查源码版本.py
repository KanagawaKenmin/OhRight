"""构建边界：核对交付清单与工程版本，阻止旧文件/混合上传被当作 0.3 验证。
输入：源码及固定交付清单；输出：逐文件校验与版本报告。
依赖：Python 标准库；--write-manifest 仅用于本地更新交付清单，CI 不自动重建。
"""
import hashlib
import json
from pathlib import Path
import re
import sys
import unicodedata


TEXT_SUFFIXES = {'.swift', '.py', '.sh', '.yml', '.env', '.json', '.plist', '.xcprivacy', '.svg'}
MANIFEST = '构建/源码清单.json'


def digest(path):
    content = path.read_bytes()
    if path.suffix in TEXT_SUFFIXES:
        content = content.decode('utf-8-sig').replace('\r\n', '\n').encode('utf-8')
    return hashlib.sha256(content).hexdigest()


def source_files(root):
    paths = [root / name for name in ('Package.swift', 'project.yml', 'codemagic.yaml')]
    for directory in ('应用', '测试', '资源', '构建'):
        paths.extend(path for path in (root / directory).rglob('*') if path.is_file()
                     and path.suffix in TEXT_SUFFIXES.union({'.png', '.jpg', '.jpeg'})
                     and path != root / MANIFEST)
    return {unicodedata.normalize('NFC', path.relative_to(root).as_posix()): digest(path)
            for path in sorted(paths)}


def project_version(root):
    project = (root / 'project.yml').read_text(encoding='utf-8-sig')
    version = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', project)
    build = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', project)
    if not version or not build:
        raise RuntimeError('Project version is missing')
    return version[1], build[1]


def verify(root):
    manifest = json.loads((root / MANIFEST).read_text(encoding='utf-8'))
    actual = source_files(root)
    missing = sorted(set(manifest['files']) - set(actual))
    extra = sorted(set(actual) - set(manifest['files']))
    changed = sorted(name for name in set(actual).intersection(manifest['files'])
                     if actual[name] != manifest['files'][name])
    if missing or extra or changed:
        raise RuntimeError(f'Source upload does not match the delivered package. '
                           f'Missing: {missing}; extra: {extra}; changed: {changed}')
    version, build = project_version(root)
    if (version, build) != (manifest['version'], manifest['build']):
        raise RuntimeError('Source manifest and project versions differ')
    print(f'Source version verified: {version} ({build}); {len(actual)} files match delivery manifest.', flush=True)
    return {'version': version, 'build': build, 'verifiedFiles': len(actual)}


if __name__ == '__main__':
    workspace = Path(__file__).resolve().parent.parent
    try:
        if sys.argv[1:] == ['--write-manifest']:
            version, build = project_version(workspace)
            value = {'version': version, 'build': build, 'files': source_files(workspace)}
            (workspace / MANIFEST).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
        elif not sys.argv[1:]:
            result = verify(workspace)
            (workspace / 'build').mkdir(exist_ok=True)
            (workspace / 'build/source-verification.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
        else:
            raise RuntimeError('Usage: 检查源码版本.py [--write-manifest]')
    except (RuntimeError, ValueError, OSError) as failure:
        print(f'Source verification failed: {failure}', file=sys.stderr, flush=True)
        raise SystemExit(1)
