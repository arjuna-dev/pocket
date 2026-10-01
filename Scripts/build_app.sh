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

if [[ -n "$signing_identity" ]]; then
    codesign --force --deep --sign "$signing_identity" "$app_path" >/dev/null
else
    codesign --force --deep --sign - "$app_path" >/dev/null
    echo "Warning: using ad-hoc signing; Keychain approval may reset after rebuilding."
    echo "Run ./Scripts/setup_signing.sh once to create a persistent local signing identity."
fi

echo "Built $app_path"
