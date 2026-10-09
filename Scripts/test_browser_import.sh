#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_temp_dir="$(mktemp -d "${TMPDIR:-/tmp/}pocket-browser-import-tests.XXXXXX")"
trap 'rm -rf "$test_temp_dir"' EXIT
cd "$project_dir"
xcrun swiftc -parse-as-library -swift-version 5 \
    Sources/Pocket/BrowserSessionImporter.swift \
    Tests/BrowserImportTests.swift \
    -lsqlite3 \
    -o "$test_temp_dir/browser-import-tests"
"$test_temp_dir/browser-import-tests"
