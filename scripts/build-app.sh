#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="$project_dir/build/Pēsu.app"
binary_dir="$(cd "$project_dir" && swift build -c release --show-bin-path)"
icon_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/pesu-icon.XXXXXX")"
iconset_dir="$icon_work_dir/Pēsu.iconset"
trap 'rm -rf "$icon_work_dir"' EXIT

cd "$project_dir"
swift build -c release

cd "$project_dir/website"
npm run build
cd "$project_dir"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/PesuApp" "$app_dir/Contents/MacOS/PesuApp"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/pesu-logo.png" "$app_dir/Contents/Resources/pesu-logo.png"
if [[ -d "$binary_dir/Pesu_PesuApp.bundle" ]]; then
    cp -R "$binary_dir/Pesu_PesuApp.bundle" "$app_dir/Contents/Resources/Pesu_PesuApp.bundle"
fi
mkdir -p "$app_dir/Contents/Resources/DaytonaBridge/.next"
cp -R "$project_dir/website/.next/standalone/." "$app_dir/Contents/Resources/DaytonaBridge/"
cp -R "$project_dir/website/.next/static" "$app_dir/Contents/Resources/DaytonaBridge/.next/static"
cp -R "$project_dir/website/public" "$app_dir/Contents/Resources/DaytonaBridge/public"

mkdir -p "$iconset_dir"
sips -z 16 16 "$project_dir/Resources/pesu-logo.png" --out "$iconset_dir/icon_16x16.png" >/dev/null
sips -z 32 32 "$project_dir/Resources/pesu-logo.png" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$project_dir/Resources/pesu-logo.png" --out "$iconset_dir/icon_32x32.png" >/dev/null
sips -z 64 64 "$project_dir/Resources/pesu-logo.png" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$project_dir/Resources/pesu-logo.png" --out "$iconset_dir/icon_128x128.png" >/dev/null
sips -z 256 256 "$project_dir/Resources/pesu-logo.png" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$project_dir/Resources/pesu-logo.png" --out "$iconset_dir/icon_256x256.png" >/dev/null
sips -z 512 512 "$project_dir/Resources/pesu-logo.png" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$project_dir/Resources/pesu-logo.png" --out "$iconset_dir/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$project_dir/Resources/pesu-logo.png" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/Pēsu.icns"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
