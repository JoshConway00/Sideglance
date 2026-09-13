#!/bin/zsh
set -eu
cd "${0:A:h:h}"
# Extract every application source once. Tests remain in the required Build job.
# A single frontend avoids repeated per-file work under CodeQL's Swift tracer.
# Keep optimisation disabled so analysis retains the unoptimised application code.
SCAN_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/sideglance-codeql.XXXXXX")
trap 'rm -rf "$SCAN_TEMP"' EXIT
xcrun swiftc -swift-version 5 -whole-module-optimization -Onone \
  -module-cache-path "$SCAN_TEMP/cache" -target "arm64-apple-macos14.0" \
  Sources/*.swift -o "$SCAN_TEMP/Sideglance" -framework Cocoa -framework SwiftUI
