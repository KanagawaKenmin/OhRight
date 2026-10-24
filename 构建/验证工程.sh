#!/bin/bash
# 构建边界：分阶段运行核心测试、模拟器编译、启动与串行测试。
# 输入：生成的工程；输出：阶段日志与 xcresult；失败或超时立即停止。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
export NSUnbufferedIO=YES

# 输出每 30 秒的进度并限制整阶段时长；超时终止该阶段的进程组，保留失败状态。
run_step() {
  python3 - "$@" <<'PY'
import os, signal, subprocess, sys, time
limit, label, *command = sys.argv[1:]
limit = int(limit)
started = time.monotonic()
print(f"=== {label}: START (limit {limit}s) ===", flush=True)
child = subprocess.Popen(command, start_new_session=True)

def stop():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(child.pid, sig)
        except ProcessLookupError:
            return
        try:
            child.wait(timeout=5)
            return
        except subprocess.TimeoutExpired:
            pass

def cancel(signum, frame):
    stop()
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, cancel)
signal.signal(signal.SIGINT, cancel)
while True:
    remaining = limit - (time.monotonic() - started)
    if remaining <= 0:
        print(f"=== {label}: TIMEOUT after {limit}s ===", flush=True)
        stop()
        raise SystemExit(124)
    try:
        code = child.wait(timeout=min(30, remaining))
        print(f"=== {label}: {'PASS' if code == 0 else 'FAIL'} (exit {code}) ===", flush=True)
        raise SystemExit(code if code >= 0 else 128 - code)
    except subprocess.TimeoutExpired:
        print(f"=== {label}: still running, {int(time.monotonic() - started)}s elapsed ===", flush=True)
PY
}

simulator_id=""
# App 启动/测试卡住时同时保存设备状态、模拟器系统日志和主机崩溃报告。
collect_diagnostics() {
  code=$?
  trap - EXIT
  if [[ "$code" -ne 0 ]]; then
    run_step 15 "Collect device state" xcrun simctl list devices \
      > build/simulator-failure-state.txt 2>&1 || true
    if [[ -n "$simulator_id" ]]; then
      run_step 30 "Collect simulator log" xcrun simctl spawn "$simulator_id" log show \
        --last 5m --style compact --predicate 'process CONTAINS "OhRight" OR process == "SpringBoard" OR process == "backboardd" OR process == "testmanagerd"' \
        > build/simulator-failure.log 2>&1 || true
    fi
    python3 - <<'PY'
import pathlib, shutil, time
source = pathlib.Path.home() / 'Library/Logs/DiagnosticReports'
target = pathlib.Path('build/crash-reports')
target.mkdir(exist_ok=True)
for report in source.glob('*'):
    if report.is_file() and report.stat().st_mtime > time.time() - 1800:
        shutil.copy2(report, target / report.name)
PY
  fi
  if [[ -n "$simulator_id" ]]; then
    run_step 20 "Shut down CI simulator" xcrun simctl shutdown "$simulator_id" \
      > build/simulator-shutdown.log 2>&1 || true
  fi
  exit "$code"
}
trap collect_diagnostics EXIT
run_step 30 "Verify delivered source version" python3 构建/检查源码版本.py \
  2>&1 | tee build/source-verification.log
run_step 30 "Build orchestration regression tests" python3 -m unittest discover -s 测试/构建 -p 'test_*.py' \
  2>&1 | tee build/build-script-tests.log
run_step 300 "1/5 Core tests" swift test --parallel 2>&1 | tee build/core-tests.log
run_step 360 "Prepare SDK-matched CI simulator" python3 构建/模拟器准备.py create \
  2>&1 | tee build/simulator-prepare.log
simulator_id="$(cat build/simulator-id.txt)"

# 使用当前 SDK 对应的全新专用设备；同一个 UUID 贯穿编译、启动与测试。
common=(-project OhRight.xcodeproj -scheme OhRight -configuration Debug
  -destination "platform=iOS Simulator,id=$simulator_id" -destination-timeout 60
  -derivedDataPath build/simulator -parallel-testing-enabled NO
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=-
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
run_step 480 "2/5 Build simulator app and tests" xcodebuild build-for-testing \
  "${common[@]}" 2>&1 | tee build/ios-build.log

# 必须通过 bootstatus 就绪检查；失败保留诊断，只重启本次设备并重试一次。
run_step 420 "3/5 Boot simulator" python3 构建/模拟器准备.py boot "$simulator_id" \
  2>&1 | tee build/simulator-boot.log

test_options=(-test-timeouts-enabled YES -default-test-execution-time-allowance 120
  -maximum-test-execution-time-allowance 180)
run_step 180 "4/5 iOS unit and storage tests" xcodebuild test-without-building \
  "${common[@]}" "${test_options[@]}" -only-testing:OhRightTests \
  -resultBundlePath "build/UnitTests-$(date +%s).xcresult" 2>&1 | tee build/ios-unit-tests.log
run_step 300 "5/5 UI tests" xcodebuild test-without-building \
  "${common[@]}" "${test_options[@]}" -only-testing:OhRightUITests \
  -resultBundlePath "build/UITests-$(date +%s).xcresult" 2>&1 | tee build/ios-ui-tests.log
echo "All five verification stages passed."
