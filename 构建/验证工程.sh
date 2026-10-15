#!/bin/bash
# 构建边界：运行核心测试与 iPhone 模拟器测试。
# 输入：生成的工程；输出：xcresult 与日志；失败立即停止。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swift test --parallel 2>&1 | tee build/core-tests.log
simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
data = json.load(sys.stdin)
devices = [d for runtime, values in data["devices"].items() if "iOS" in runtime for d in values if d.get("isAvailable") and d["name"].startswith("iPhone")]
devices.sort(key=lambda d: ("iPhone 17" not in d["name"], d["name"]))
if not devices: raise SystemExit("No available iPhone simulator")
print(devices[0]["udid"])
')"
printf '%s\n' "$simulator_id" > build/simulator-id.txt
xcodebuild test -project OhRight.xcodeproj -scheme OhRight \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath build/simulator -resultBundlePath "build/Tests-$(date +%s).xcresult" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/ios-tests.log
