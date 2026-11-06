#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p .build/tools Assets
xcrun swiftc tools/encode-alpha.swift -module-cache-path .build/ModuleCache -o .build/tools/encode-alpha
for kind in water walk eyes; do
  target="Assets/gugugaga-${kind}-alpha.mov"
  staging="Assets/gugugaga-${kind}-alpha.new.mov"
  if [[ -e "$staging" ]]; then
    echo "存在上次未完成的转换文件，请先检查：$staging" >&2
    exit 1
  fi
  ffmpeg -v error -c:v libvpx-vp9 -i "SourceAssets/gugugaga-${kind}-alpha.webm" -an -f rawvideo -pix_fmt bgra - |
    .build/tools/encode-alpha "$staging" 1080 1080 24
  mv "$staging" "$target"
done
