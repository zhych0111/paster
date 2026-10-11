#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
cd "$repo_dir"
swift build -c release --product Paster
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$repo_dir/dist/Paster.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Paster" "$app_dir/Contents/MacOS/Paster"
cp "$repo_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$repo_dir/Resources/Paster.icns" "$app_dir/Contents/Resources/Paster.icns"
chmod 755 "$app_dir/Contents/MacOS/Paster"
codesign --force --sign - "$app_dir"
echo "$app_dir"
