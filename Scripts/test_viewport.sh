#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_temp_dir="$(mktemp -d "${TMPDIR:-/tmp/}pocket-viewport-tests.XXXXXX")"
trap 'rm -rf "$test_temp_dir"' EXIT
cd "$project_dir"
xcrun swiftc -parse-as-library -swift-version 5 \
    Sources/Pocket/ScreenLayout.swift Sources/Pocket/Models.swift Sources/Pocket/WebViewController.swift \
    Tests/ResponsiveViewportTests.swift -o "$test_temp_dir/viewport-tests"
"$test_temp_dir/viewport-tests"
