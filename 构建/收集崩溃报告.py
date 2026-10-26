"""构建边界：尽力复制本次近期崩溃报告；读写失败不阻断验证清理。
输入：系统诊断目录；输出：build/crash-reports；整步由验证脚本限时。
"""
from pathlib import Path
import shutil
import time


def collect(source, target):
    try:
        target.mkdir(parents=True, exist_ok=True)
        for report in source.glob('*'):
            try:
                if report.is_file() and report.stat().st_mtime > time.time() - 1800:
                    shutil.copy2(report, target / report.name)
            except OSError as error:
                print(f'Crash report unavailable: {report.name}: {error}', flush=True)
    except OSError as error:
        print(f'Crash report collection unavailable: {error}', flush=True)


if __name__ == '__main__':
    collect(Path.home() / 'Library/Logs/DiagnosticReports', Path('build/crash-reports'))
