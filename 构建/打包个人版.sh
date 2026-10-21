#!/bin/bash
# 构建边界：生成真实 iOS 设备未签名 IPA 和 SHA-256。
# 输入：工程；输出：build/artifacts；无 Apple ID、无分发上传。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/artifacts
xcodebuild build -project OhRight.xcodeproj -scheme OhRight -configuration PersonalTrial \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym 2>&1 | tee build/device-build.log
app_path="$PWD/build/device/Build/Products/PersonalTrial-iphoneos/OhRight.app"
binary_path="$app_path/OhRight"
test -f "$binary_path"
xcrun vtool -show-build "$binary_path" > build/artifacts/device-platform.txt
if ! grep -Eq 'platform +IOS$' build/artifacts/device-platform.txt; then
  echo "Output is not an iOS device binary" >&2
  exit 1
fi
stage_path="$(mktemp -d "$PWD/build/package.XXXXXX")"
mkdir -p "$stage_path/Payload"
ditto "$app_path" "$stage_path/Payload/OhRight.app"
ipa_path="$PWD/build/artifacts/OhRight-personal-unsigned.ipa"
(cd "$stage_path" && /usr/bin/zip -qry "$stage_path/OhRight.ipa" Payload)
mv "$stage_path/OhRight.ipa" "$ipa_path"
unzip -t "$ipa_path" > build/artifacts/ipa-check.txt
shasum -a 256 "$ipa_path" > "$ipa_path.sha256"
cp build/toolchain.txt build/artifacts/toolchain.txt
python3 - <<'PY'
import json, os, pathlib, plistlib, subprocess
root = pathlib.Path('build/artifacts')
app_info = plistlib.loads(pathlib.Path('build/device/Build/Products/PersonalTrial-iphoneos/OhRight.app/Info.plist').read_bytes())
try:
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
except subprocess.CalledProcessError:
    commit = 'unversioned'
info = {'product':'OhRight', 'version':app_info['CFBundleShortVersionString'],
        'build':app_info['CFBundleVersion'], 'minimumIOS':app_info['MinimumOSVersion'],
        'signing':'unsigned: sign locally before install', 'commit':commit,
        'buildID':os.getenv('CM_BUILD_ID', 'manual')}
(root / 'build-info.json').write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding='utf-8')
PY
