#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED_DATA="$ROOT/.build/XcodeSigned"
PRODUCT="$DERIVED_DATA/Build/Products/Debug/OmniVim.app"
APP="$ROOT/OmniVim.app"

export DEVELOPER_DIR

xcodebuild \
  -project "$ROOT/OmniVim.xcodeproj" \
  -scheme OmniVim \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'platform=macOS,arch=arm64' \
  build

rm -rf "$APP"
/usr/bin/ditto "$PRODUCT" "$APP"
echo "Built $APP"
