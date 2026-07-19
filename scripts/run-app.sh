#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/App/OmniVim.app"

"$ROOT/scripts/build-app.sh"
pkill -x OmniVim || true
open "$APP"
echo "Opened $APP"
