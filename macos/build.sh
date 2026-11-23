#!/bin/bash
# Build "Port Dashboard.app" (chay duoc tren Mac Apple Silicon va Intel, macOS 14+).
# Can Xcode hoac Command Line Tools:  xcode-select --install
#   ./build.sh            -> build/Port Dashboard.app
#   ./build.sh --install  -> build roi chep vao /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Port Dashboard.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Đang biên dịch..."
for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos14.0" \
        PortDashboard.swift -o "build/PortDashboard-$arch"
done
lipo -create build/PortDashboard-arm64 build/PortDashboard-x86_64 -output "$APP/Contents/MacOS/PortDashboard"
rm build/PortDashboard-arm64 build/PortDashboard-x86_64
cp Info.plist "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then   # vd VERSION=v1.2.0 (CI truyen ten tag) -> 1.2.0
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$APP/Contents/Info.plist"
fi

echo "Đang vẽ icon..."
swift make_icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf build/AppIcon.iconset

xattr -cr "$APP"                          # bo thuoc tinh mo rong (Finder, tai ve...) truoc khi ky
codesign --force --deep --sign - "$APP"   # ky ad-hoc de macOS cho chay
echo "Xong: macos/$APP"

if [ "${1:-}" = "--install" ]; then
    rm -rf "/Applications/Port Dashboard.app"
    cp -R "$APP" /Applications/
    echo "Đã chép vào /Applications/Port Dashboard.app"
fi
