#!/bin/zsh
set -eu
cd "${0:A:h}"
APP="$PWD/build/Sideglance.app"
BUILD_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/sideglance-build.XXXXXX")
trap 'rm -rf "$BUILD_TEMP"' EXIT
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_TEMP/cache" -target "arm64-apple-macos14.0" Sources/*.swift -o "$APP/Contents/MacOS/Sideglance" -framework Cocoa -framework SwiftUI
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Sideglance</string>
<key>CFBundleIdentifier</key><string>au.com.sideglance.local</string>
<key>CFBundleName</key><string>Sideglance</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
TEST_SOURCES=()
for source_file in Sources/*.swift; do
    if [[ "$source_file" != Sources/main.swift ]]; then TEST_SOURCES+=("$source_file"); fi
done
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_TEMP/cache" -target "arm64-apple-macos14.0" "${TEST_SOURCES[@]}" Tests/*.swift -o build/SideglanceTests -framework Cocoa -framework SwiftUI
build/SideglanceTests
