#!/bin/bash
# Chup anh giao dien cho README bang du lieu demo (khong lo port/ten nguoi dung that):
#   ./screenshot.sh  -> docs/images/macos-light.png, docs/images/macos-dark.png
set -euo pipefail
cd "$(dirname "$0")"

APP="build/screenshot/Port Dashboard.app"
OUT="$(cd .. && pwd)/docs/images"
rm -rf build/screenshot
mkdir -p "$APP/Contents/MacOS" "$OUT"
swiftc -swift-version 5 -parse-as-library -D SCREENSHOT PortDashboard.swift -o "$APP/Contents/MacOS/PortDashboard"
cp Info.plist "$APP/Contents/Info.plist"
# bundle id rieng -> dung cai dat mac dinh, khong dung cai dat cua ban dang dung
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.github.luckydung.portwatch.screenshot" "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force --sign - "$APP" 2>/dev/null

open -W -n --env SCREENSHOT_OUT="$OUT/macos-light.png" "$APP"
open -W -n --env SCREENSHOT_OUT="$OUT/macos-dark.png" --env SCREENSHOT_DARK=1 "$APP"
ls -l "$OUT"
