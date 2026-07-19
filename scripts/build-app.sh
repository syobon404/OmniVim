#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED_DATA="$ROOT/.build/XcodeSigned"
PRODUCT="$DERIVED_DATA/Build/Products/Debug/OmniVim.app"
APP_DIRECTORY="$ROOT/.build/App"
APP="$APP_DIRECTORY/OmniVim.app"
RUNTIME_MODEL="$ROOT/Resources/Models/GPA_GUI_Detector.mlpackage"

if [ ! -f "$RUNTIME_MODEL/Manifest.json" ] || [ ! -d "$RUNTIME_MODEL/Data" ]; then
  echo "Bundled GPA model is missing: $RUNTIME_MODEL" >&2
  echo "Restore the tracked Resources/Models directory and try again." >&2
  echo "Maintainers can generate a replacement with the documented conversion workflow." >&2
  exit 1
fi

export DEVELOPER_DIR

xcodebuild \
  -project "$ROOT/OmniVim.xcodeproj" \
  -scheme OmniVim \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'platform=macOS,arch=arm64' \
  build

mkdir -p "$APP_DIRECTORY"
rm -rf "$APP"
/usr/bin/ditto "$PRODUCT" "$APP"
echo "Built $APP"
