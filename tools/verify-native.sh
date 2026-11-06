#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
if [[ "$(uname -m)" == "arm64" ]]; then output_dir="dist/mac-arm64"; else output_dir="dist/mac-x64"; fi
mkdir -p artifacts/native-qa
qa_dir="$(mktemp -d "$project_root/artifacts/native-qa/run-XXXXXX")"
"$output_dir/Golden Paw.app/Contents/MacOS/GuguReminder" --verify "$qa_dir"
echo "验证记录：$qa_dir/native-qa.json"
