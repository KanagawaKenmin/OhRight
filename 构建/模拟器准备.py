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


def open_simulator(identifier=None):
    """提前启动当前 Xcode 的 Simulator，让首次运行时查询有机会完成服务初始化。"""
    developer = os.environ.get('DEVELOPER_DIR') or command(['xcode-select', '-p'], timeout=10)
    arguments = ['open', '-a', str(Path(developer) / 'Applications/Simulator.app')]
    if identifier:
        arguments += ['--args', '-CurrentDeviceUDID', identifier]
    command(arguments, timeout=10)


def runtime_list(root):
    """冷启动查询最多两次，每次 90 秒；失败保留宿主诊断，不能伪造可用运行时。"""
    attempts = []
    try:
        for attempt in (1, 2):
            try:
                open_simulator()
            except (subprocess.SubprocessError, OSError) as error:
                print(f'Simulator warm-up unavailable; runtime discovery is still required: {error}', flush=True)
            try:
                output = command(['xcrun', 'simctl', 'list', 'runtimes', '--json'], timeout=90)
                runtimes = json.loads(output)
                if not isinstance(runtimes.get('runtimes'), list):
                    raise ValueError('Runtime response does not contain a runtimes list')
                attempts.append({'attempt': attempt, 'ready': True})
                return runtimes
            except (subprocess.SubprocessError, OSError) as error:
                attempts.append({'attempt': attempt, 'ready': False, 'error': str(error)})
                try:
                    diagnostics = command(['ps', '-axo', 'pid,etime,comm'], timeout=10)
                    (root / f'simulator-discovery-attempt-{attempt}.txt').write_text(diagnostics, encoding='utf-8')
                except (subprocess.SubprocessError, OSError) as diagnostic_error:
                    print(f'Host diagnostics unavailable: {diagnostic_error}', flush=True)
                try:
                    service_log = command(['log', 'show', '--last', '2m', '--style', 'compact', '--predicate',
                                           'process == "CoreSimulatorService" OR process == "simdiskimaged"'], timeout=10)
                    (root / f'simulator-service-attempt-{attempt}.log').write_text(service_log, encoding='utf-8')
                except (subprocess.SubprocessError, OSError) as diagnostic_error:
                    print(f'Simulator service log unavailable: {diagnostic_error}', flush=True)
                if attempt == 2:
                    raise RuntimeError('Simulator runtime discovery failed twice; no device or test results were assumed') from error
                print('Runtime discovery did not finish; reopening Simulator before one retry.', flush=True)
    finally:
        (root / 'simulator-discovery-result.json').write_text(json.dumps(attempts, indent=2), encoding='utf-8')


def create_device(root):
    root.mkdir(parents=True, exist_ok=True)
    sdk = command(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'])
    runtimes = runtime_list(root)
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
                open_simulator(identifier)
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
