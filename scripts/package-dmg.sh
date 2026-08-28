#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")"
artifact_name="Pēsu-${version}-macOS26-arm64"
app_dir="$project_dir/build/Pēsu.app"
dist_dir="$project_dir/dist"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/pesu-dmg.XXXXXX")"
dmg_path="$dist_dir/$artifact_name.dmg"
checksum_path="$dmg_path.sha256"
trap 'rm -rf "$staging_dir"' EXIT

"$project_dir/scripts/build-app.sh" >/dev/null

codesign --verify --deep --strict --verbose=2 "$app_dir"
if otool -L "$app_dir/Contents/MacOS/PesuApp" | grep -q '/opt/homebrew\|/usr/local'; then
    echo "Packaging stopped: the app contains a machine-specific library path." >&2
    exit 1
fi

mkdir -p "$dist_dir"
rm -f "$dmg_path" "$checksum_path"
cp -R "$app_dir" "$staging_dir/Pēsu.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "Pēsu $version" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path" >/dev/null

checksum="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
printf '%s  %s\n' "$checksum" "${dmg_path:t}" > "$checksum_path"

echo "$dmg_path"
echo "$checksum_path"
