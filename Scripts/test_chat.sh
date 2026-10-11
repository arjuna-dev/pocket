#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_temp_dir="$(mktemp -d "${TMPDIR:-/tmp/}pocket-chat-tests.XXXXXX")"
trap 'rm -rf "$test_temp_dir"' EXIT
cd "$project_dir"
chmod +x Tests/Fixtures/chat_app_server.py
xcrun swiftc -parse-as-library -swift-version 5 \
    Sources/Pocket/Models.swift Sources/Pocket/WebViewController.swift Sources/Pocket/ScreenLayout.swift \
    Sources/Pocket/PocketWorkspace.swift Sources/Pocket/CodexAppServerClient.swift Sources/Pocket/PocketChatController.swift \
    Sources/Pocket/ScreenActivity.swift \
    Sources/Pocket/WindowManager.swift Tests/PocketChatTests.swift -o "$test_temp_dir/chat-tests"
"$test_temp_dir/chat-tests" "$project_dir/Tests/Fixtures/chat_app_server.py"
