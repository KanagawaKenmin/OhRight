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

run_step 300 "1/5 Core tests" swift test --parallel 2>&1 | tee build/core-tests.log
echo "Selecting an available iPhone simulator with iOS 26 or later..."
simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
data = json.load(sys.stdin)
devices = [d for runtime, values in data["devices"].items()
           if (match := re.search(r"\.iOS-(\d+)-", runtime)) and int(match[1]) >= 26
           for d in values if d.get("isAvailable") and d["name"].startswith("iPhone")]
devices.sort(key=lambda d: ("iPhone 17" not in d["name"], d["name"]))
if not devices: raise SystemExit("No available iPhone simulator with iOS 26 or later")
print(devices[0]["udid"])
')"
printf '%s\n' "$simulator_id" > build/simulator-id.txt
echo "Selected simulator: $simulator_id"
xcrun simctl list devices available > build/simulators.txt

# 先只编译，避免把编译和测试启动混成一个无法判断的等待阶段。
# 模拟器使用无账号的本机临时签名；设备 IPA 仍由独立脚本生成未签名版本。
common=(-project OhRight.xcodeproj -scheme OhRight -configuration Debug
  -destination "platform=iOS Simulator,id=$simulator_id" -destination-timeout 60
  -derivedDataPath build/simulator -parallel-testing-enabled NO
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=-
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
# App 启动/测试卡住时同时保存设备状态、模拟器系统日志和主机崩溃报告。
collect_diagnostics() {
  code=$?
  trap - EXIT
  if [[ "$code" -ne 0 ]]; then
    xcrun simctl list devices > build/simulator-failure-state.txt 2>&1 || true
    run_step 30 "Collect simulator log" xcrun simctl spawn "$simulator_id" log show \
      --last 5m --style compact --predicate 'process CONTAINS "OhRight" OR process == "SpringBoard" OR process == "testmanagerd"' \
      > build/simulator-failure.log 2>&1 || true
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
  exit "$code"
}
trap collect_diagnostics EXIT
run_step 480 "2/5 Build simulator app and tests" xcodebuild build-for-testing \
  "${common[@]}" 2>&1 | tee build/ios-build.log

# bootstatus -b 同时启动或等待已启动的设备，且不会因为设备已启动而报重复启动。
run_step 180 "3/5 Boot simulator" xcrun simctl bootstatus "$simulator_id" -b \
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
