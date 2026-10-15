#!/bin/bash
# 构建边界：下载已锁定源码生成工程；输出 build/tools 下工具。
# 输入：工具版本.env；失败：版本或提交不匹配即停止；不配置签名。
set -euo pipefail
cd "$(dirname "$0")/.."
source 构建/工具版本.env
mkdir -p build/tools
actual_xcode="$(xcodebuild -version | head -n 1 | awk '{print $2}')"
if [[ "$actual_xcode" != "$XCODE_VERSION" ]]; then
  echo "Xcode mismatch: expected $XCODE_VERSION, received $actual_xcode" >&2
  exit 1
fi
tool_root="$PWD/build/tools/XcodeGen"
if [[ ! -d "$tool_root/.git" ]]; then
  git clone --depth 1 --branch "$XCODEGEN_VERSION" https://github.com/yonaskolb/XcodeGen.git "$tool_root"
fi
tool_revision="$(git -C "$tool_root" rev-parse HEAD)"
if [[ "$tool_revision" != "$XCODEGEN_COMMIT" ]]; then
  echo "XcodeGen commit mismatch" >&2
  exit 1
fi
(cd "$tool_root" && swift build -c release --product xcodegen)
"$tool_root/.build/release/xcodegen" generate --spec project.yml
xcodebuild -version > build/toolchain.txt
printf 'XcodeGen %s %s\n' "$XCODEGEN_VERSION" "$tool_revision" >> build/toolchain.txt
