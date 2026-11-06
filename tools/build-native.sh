#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/ModuleCache"
architecture="$(uname -m)"
if [[ "$architecture" == "arm64" ]]; then output_dir="dist/mac-arm64"; else output_dir="dist/mac-x64"; fi
app_path="$output_dir/Golden Paw.app"

xcrun swift build --disable-sandbox -c release --scratch-path .build --cache-path .build/SwiftPMCache
binary_dir="$(xcrun swift build --disable-sandbox -c release --scratch-path .build --cache-path .build/SwiftPMCache --show-bin-path)"

# 新构建先放暂存目录，成功后再替换应用；旧版存为 tar，避免被系统识别为另一份应用。
staging="$output_dir/Golden Paw.new.app"
mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources/Assets"
cp "$binary_dir/GuguReminder" "$staging/Contents/MacOS/GuguReminder"
for kind in water walk eyes; do
  cp "Assets/gugugaga-${kind}-alpha.mov" "Assets/gugugaga-${kind}-rest.png" "$staging/Contents/Resources/Assets/"
done
cat > "$staging/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.zoey.goldenpaw</string>
  <key>CFBundleName</key><string>Golden Paw</string>
  <key>CFBundleDisplayName</key><string>咕咕提醒</string>
  <key>CFBundleExecutable</key><string>GuguReminder</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$staging"
if [[ -d "$app_path" ]]; then
  archive="artifacts/local-builds/previous-app.tar"
  previous="$output_dir/Golden Paw.previous"
  if [[ -e "$previous" ]]; then
    echo "存在上次未完成的替换，请先检查：$previous" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$archive")"
  tar -cf "$archive.tmp" -C "$output_dir" "Golden Paw.app"
  mv "$archive.tmp" "$archive"
  mv "$app_path" "$previous"
  if ! mv "$staging" "$app_path"; then
    mv "$previous" "$app_path"
    exit 1
  fi
  rm -rf "$previous"
else
  mv "$staging" "$app_path"
fi
echo "已构建原生应用：$project_root/$app_path"
du -sh "$app_path"
