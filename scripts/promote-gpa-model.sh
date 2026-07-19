#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$ROOT/Models/Generated/GPA_GUI_Detector.mlpackage}"
DESTINATION_DIRECTORY="$ROOT/Resources/Models"
DESTINATION="$DESTINATION_DIRECTORY/GPA_GUI_Detector.mlpackage"

if [ ! -f "$SOURCE/Manifest.json" ] || [ ! -d "$SOURCE/Data" ]; then
    echo "Invalid or missing generated GPA model: $SOURCE" >&2
    echo "Generate it first with: python Tools/ModelConversion/GPA/convert.py" >&2
    exit 1
fi

mkdir -p "$DESTINATION_DIRECTORY"
rm -rf "$DESTINATION"
/usr/bin/ditto "$SOURCE" "$DESTINATION"
echo "Promoted GPA model to $DESTINATION"
