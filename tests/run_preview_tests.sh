#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
DEVICE=
cleanup() {
    if [ -n "$DEVICE" ]; then
        xcrun simctl shutdown "$DEVICE" >/dev/null 2>&1 || true
        xcrun simctl delete "$DEVICE" >/dev/null 2>&1 || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT
xcrun simctl list runtimes -j > "$TMP/runtimes.json"
RUNTIME=$(python3 -c 'import json,sys; a=[r for r in json.load(open(sys.argv[1]))["runtimes"] if r.get("isAvailable") and "iOS" in r["name"]]; assert a,"No iOS simulator runtime installed"; print(sorted(a,key=lambda r:tuple(map(int,r["version"].split("."))))[-1]["identifier"])' "$TMP/runtimes.json")
DEVICE=$(xcrun simctl create TVZPreviewTests com.apple.CoreSimulator.SimDeviceType.iPhone-16 "$RUNTIME")
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
APP="$TMP/TVZPreviewTests.app"
mkdir -p "$APP"
export TVZ_TEST_APP="$APP"
python3 -c 'import os,plistlib; plistlib.dump({"CFBundleIdentifier":"com.82flex.touchviz.previewtests","CFBundleExecutable":"TVZPreviewTests","CFBundleName":"TVZPreviewTests","CFBundlePackageType":"APPL","CFBundleVersion":"1","CFBundleShortVersionString":"1","LSRequiresIPhoneOS":True,"UIDeviceFamily":[1],"UILaunchScreen":{},"UISupportedInterfaceOrientations":["UIInterfaceOrientationPortrait"]},open(os.environ["TVZ_TEST_APP"]+"/Info.plist","wb"))'
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-ios18.5-simulator" -sdk "$SDK" \
    TVZPrefs/TVZTouchVizSelection.swift TVZPrefs/TVZTouchVizImagePreview.swift tests/preview_test.swift \
    -o "$APP/TVZPreviewTests"
codesign --force --sign - "$APP"
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch "$DEVICE" com.82flex.touchviz.previewtests
DATA=$(xcrun simctl get_app_container "$DEVICE" com.82flex.touchviz.previewtests data)
python3 - "$DATA/Documents/preview-result.txt" <<'PY'
from pathlib import Path
import sys,time
result=Path(sys.argv[1]); deadline=time.monotonic()+90
while not result.exists() and time.monotonic()<deadline:
    time.sleep(0.5)
if not result.exists(): raise SystemExit('FAIL simulator preview result timeout')
text=result.read_text(); print(text)
if not text.startswith('PASS '): raise SystemExit(1)
PY
