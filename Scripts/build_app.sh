#!/bin/zsh

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-release}"
configuration_flag="-c"
signing_identity="${POCKET_SIGNING_IDENTITY:-}"

if [[ -z "$signing_identity" ]]; then
    signing_identity="$(security find-identity -p codesigning | awk '/"Pocket Local Development"/ { print $2; exit }')"
fi

cd "$project_dir"
swift build "$configuration_flag" "$configuration"

binary_path="$project_dir/.build/arm64-apple-macosx/$configuration/Pocket"
if [[ ! -x "$binary_path" ]]; then
    binary_path="$project_dir/.build/$configuration/Pocket"
fi

app_path="$project_dir/Pocket.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_path" "$app_path/Contents/MacOS/Pocket"
cp "$project_dir/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"

# Bundle the native helper so chat also works when Pocket is launched from Finder.
# POCKET_CODEX_BINARY can select another compatible native Codex installation.
codex_binary="${POCKET_CODEX_BINARY:-}"
if [[ -z "$codex_binary" ]]; then
    codex_arch="arm64"
    codex_target="aarch64-apple-darwin"
    if [[ "$(uname -m)" != "arm64" ]]; then
        codex_arch="x64"
        codex_target="x86_64-apple-darwin"
    fi
    codex_suffix="@openai/codex/node_modules/@openai/codex-darwin-$codex_arch/vendor/$codex_target/bin/codex"
    for candidate in "$HOME/.local/lib/node_modules/$codex_suffix" "/opt/homebrew/lib/node_modules/$codex_suffix" "/usr/local/lib/node_modules/$codex_suffix"; do
        if [[ -x "$candidate" ]]; then
            codex_binary="$candidate"
            break
        fi
    done
fi
if [[ -n "$codex_binary" && -x "$codex_binary" ]]; then
    mkdir -p "$app_path/Contents/Helpers"
    cp "$codex_binary" "$app_path/Contents/Helpers/codex"
    chmod 755 "$app_path/Contents/Helpers/codex"
else
    rm -f "$app_path/Contents/Helpers/codex"
    echo "Warning: Codex is not installed; Pocket chat will be unavailable."
fi

if [[ -n "$signing_identity" ]]; then
    codesign --force --deep --sign "$signing_identity" "$app_path" >/dev/null
else
    codesign --force --deep --sign - "$app_path" >/dev/null
    echo "Warning: using ad-hoc signing; Keychain approval may reset after rebuilding."
    echo "Run ./Scripts/setup_signing.sh once to create a persistent local signing identity."
fi

echo "Built $app_path"
