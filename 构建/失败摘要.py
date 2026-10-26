"""构建边界：仅汇总本次登记的阶段日志，保留首个具体错误及原退出码。
输入：build 内的当前日志清单、退出码和运行模式；输出：JSON 报告与末尾摘要。
依赖：Python 标准库；摘要不改变原验证结果，不扫描旧日志或用户目录。
"""
import json
from pathlib import Path
import re
import sys


def summarize(root, exit_code, mode='full'):
    """按执行顺序读取登记日志；拒绝 build 目录外路径，诊断读取错误记录但不抛出。"""
    root = Path(root).resolve()
    inventory = root / 'verification-current-logs.txt'
    result = {'exitCode': exit_code, 'mode': mode, 'stages': [], 'failedTests': [],
              'firstError': None, 'timeouts': [], 'diagnosticErrors': []}
    errors = []
    names = inventory.read_text(encoding='utf-8').splitlines() if inventory.is_file() else []
    for name in dict.fromkeys(names):
        path = (root / name).resolve()
        if path.parent != root:
            result['diagnosticErrors'].append(f'Refused log outside build: {name}')
            continue
        try:
            lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
        except OSError as error:
            result['diagnosticErrors'].append(f'{name}: {error}')
            continue
        stage = {'log': name, 'status': 'unknown'}
        for i, line in enumerate(lines):
            started = re.match(r'=== (.+): START \(limit ([\d.]+)s\) ===', line)
            ended = re.match(r'=== (.+): (PASS|FAIL) \(exit (-?\d+)\) ===', line)
            elapsed = re.match(r'=== Stage elapsed: ([\d.]+)s ===', line)
            if started:
                stage.update(label=started[1], limitSeconds=float(started[2]), status='running')
            if ended:
                stage.update(label=ended[1], status=ended[2].lower(), exitCode=int(ended[3]))
            if elapsed:
                stage['elapsedSeconds'] = float(elapsed[1])
            if 'TIMEOUT after' in line:
                result['timeouts'].append({'log': name, 'line': i + 1, 'message': line})
                stage['status'] = 'timeout'
            if re.search(r"Test Case .* failed|[✘✗] Test .*failed", line):
                result['failedTests'].append({'log': name, 'line': i + 1, 'message': line})
            if re.search(r'error:|UI verification failure:|[✘✗] Test .*failed', line):
                errors.append({'log': name, 'line': i + 1, 'message': line,
                               'context': lines[max(0, i - 2):i + 3]})
        result['stages'].append(stage)
    passed_logs = {row['log'] for row in result['stages'] if row['status'] == 'pass'}
    result['firstError'] = next((row for row in errors if row['log'] not in passed_logs), None)
    error = result['firstError']
    text = error['message'] if error else ''
    if exit_code == 0:
        kind = 'passed' if mode == 'full' else 'diagnostic_passed'
    elif re.search(r'XCTAssert|UI verification failure:|threw error', text):
        kind = 'assertion_failure'
    elif result['failedTests']:
        kind = 'test_failure'
    elif result['timeouts'] or exit_code == 124:
        kind = 'infrastructure_timeout'
    elif error and error['log'] in {'ios-build.log', 'core-tests.log'}:
        kind = 'build_failure'
    else:
        kind = 'verification_failure'
    result['primaryFailure'] = kind
    result['termination'] = 'timeout' if result['timeouts'] or exit_code == 124 else 'exit'
    return result


def render(result):
    """限制末尾摘要长度，但首个具体错误始终保留。"""
    print('=== Verification summary ===', flush=True)
    print(f"Mode: {result['mode']}; original exit: {result['exitCode']}; "
          f"primary: {result['primaryFailure']}; termination: {result['termination']}", flush=True)
    for row in result['failedTests'][:10]:
        print(f"FAILED {row['log']}:{row['line']}: {row['message']}", flush=True)
    for row in result['timeouts'][-3:]:
        print(f"TIMEOUT {row['log']}:{row['line']}: {row['message']}", flush=True)
    if result['firstError']:
        error = result['firstError']
        print(f"FIRST ERROR {error['log']}:{error['line']}", flush=True)
        for line in error['context']:
            print(line, flush=True)
    print('Full result: build/verification-result.json', flush=True)


if __name__ == '__main__':
    summary = summarize(Path('build'), int(sys.argv[1]), sys.argv[2])
    Path('build/verification-result.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    render(summary)
