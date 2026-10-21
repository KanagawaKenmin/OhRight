"""构建边界：按当前 SDK 创建专用模拟器，有限重试启动并保留失败证据。
输入：simctl 的运行时列表与专用设备 ID；输出：设备选择/启动诊断。
依赖：Python 标准库、Xcode；只重启本次创建的 CI 设备，不清除其他设备。
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid


def matching_runtime(runtimes, sdk):
    """选择与 SDK 主次版本一致的可用运行时；缺失时明确失败，不跨版本兜底。"""
    version = tuple(int(part) for part in sdk.strip().split('.'))
    candidates = [value for value in runtimes
                  if value.get('isAvailable') and '.iOS-' in value.get('identifier', '')
                  and tuple(int(part) for part in value['version'].split('.'))[:2] == version[:2]]
    if not candidates:
        raise RuntimeError(f'No available iOS runtime matching simulator SDK {sdk}')
    return max(candidates, key=lambda value: (
        value['version'] == sdk, tuple(int(part) for part in value['version'].split('.'))))


def command(arguments, timeout=30):
    """每条命令单独限时；失败保留输出并向上抛错，不能伪造设备就绪。"""
    print('+ ' + ' '.join(arguments), flush=True)
    try:
        result = subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=timeout)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        for output in (error.stdout, error.stderr):
            if output:
                print(output.decode(errors='replace') if isinstance(output, bytes) else output, flush=True)
        raise
    if result.stderr:
        print(result.stderr, flush=True)
    return result.stdout.strip()


def create_device(root):
    root.mkdir(parents=True, exist_ok=True)
    sdk = command(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'])
    runtimes = json.loads(command(['xcrun', 'simctl', 'list', 'runtimes', '--json']))
    (root / 'simulator-runtimes.json').write_text(json.dumps({'sdk': sdk, **runtimes}, indent=2), encoding='utf-8')
    runtime = matching_runtime(runtimes['runtimes'], sdk)
    device_type = 'com.apple.CoreSimulator.SimDeviceType.iPhone-17'
    name = f'OhRight-CI-{uuid.uuid4().hex[:8]}'
    identifier = command(['xcrun', 'simctl', 'create', name, device_type, runtime['identifier']])
    uuid.UUID(identifier)
    selection = {'sdk': sdk, 'runtime': runtime['identifier'], 'runtimeVersion': runtime['version'],
                 'deviceType': device_type, 'deviceName': name, 'udid': identifier}
    (root / 'simulator-selection.json').write_text(json.dumps(selection, indent=2), encoding='utf-8')
    (root / 'simulator-id.txt').write_text(identifier + '\n', encoding='utf-8')
    print(json.dumps(selection), flush=True)
    return identifier


def snapshot(root, identifier, attempt):
    for suffix, arguments in [
        ('json', ['xcrun', 'simctl', 'list', 'devices', '--json']),
        ('txt', ['xcrun', 'simctl', 'spawn', identifier, 'launchctl', 'print', 'system'])]:
        try:
            output = command(arguments, timeout=10)
            (root / f'simulator-boot-attempt-{attempt}.{suffix}').write_text(output, encoding='utf-8')
        except (subprocess.SubprocessError, OSError) as error:
            print(f'Boot diagnostics unavailable: {error}', flush=True)


def boot_device(root, identifier):
    """仅允许启动选择记录中的专用设备；最多两次，失败后仍以失败退出。"""
    selection = json.loads((root / 'simulator-selection.json').read_text(encoding='utf-8'))
    if selection['udid'] != identifier or not selection['deviceName'].startswith('OhRight-CI-'):
        raise RuntimeError('Refusing to restart a device not created by this build')
    attempts = []
    try:
        for attempt in (1, 2):
            try:
                developer = os.environ.get('DEVELOPER_DIR') or command(['xcode-select', '-p'], timeout=10)
                command(['open', '-a', str(Path(developer) / 'Applications/Simulator.app'),
                         '--args', '-CurrentDeviceUDID', identifier], timeout=10)
            except (subprocess.SubprocessError, OSError) as error:
                print(f'Simulator UI could not be opened; boot readiness is still required: {error}', flush=True)
            try:
                output = command(['xcrun', 'simctl', 'bootstatus', identifier, '-b'], timeout=150)
                print(output, flush=True)
                attempts.append({'attempt': attempt, 'ready': True})
                return
            except (subprocess.SubprocessError, OSError) as error:
                attempts.append({'attempt': attempt, 'ready': False, 'error': str(error)})
                snapshot(root, identifier, attempt)
                if attempt == 2:
                    raise RuntimeError('Simulator failed readiness checks twice; tests were not skipped') from error
                print('Restarting only this build\'s CI simulator before one retry.', flush=True)
                command(['xcrun', 'simctl', 'shutdown', identifier], timeout=20)
    finally:
        (root / 'simulator-boot-result.json').write_text(json.dumps(attempts, indent=2), encoding='utf-8')


if __name__ == '__main__':
    output_root = Path('build')
    try:
        if sys.argv[1:] == ['create']:
            create_device(output_root)
        elif len(sys.argv) == 3 and sys.argv[1] == 'boot':
            boot_device(output_root, sys.argv[2])
        else:
            raise RuntimeError('Usage: 模拟器准备.py create | boot <CI device UUID>')
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as failure:
        print(f'Simulator preparation failed: {failure}', file=sys.stderr, flush=True)
        raise SystemExit(1)
