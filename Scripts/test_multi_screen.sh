#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_temp_dir="$(mktemp -d "${TMPDIR:-/tmp/}pocket-multi-screen-tests.XXXXXX")"
trap 'rm -rf "$test_temp_dir"' EXIT
cd "$project_dir"
xcrun swiftc -parse-as-library -swift-version 5 \
    Sources/Pocket/Models.swift Sources/Pocket/WebViewController.swift \
    Sources/Pocket/ScreenLayout.swift Sources/Pocket/ScreenActivity.swift \
    Sources/Pocket/MultiScreenView.swift Sources/Pocket/Views.swift \
    Sources/Pocket/WindowManager.swift Tests/MultiScreenTests.swift \
    -o "$test_temp_dir/multi-screen-tests"
"$test_temp_dir/multi-screen-tests"
