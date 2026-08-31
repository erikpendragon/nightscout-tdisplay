#!/bin/bash
# Cuts a firmware release. Publishes TWO images:
#
#   cgm-display.factory.bin   full image (bootloader + partitions + app) for a
#                             blank board - esptool, or a browser flasher
#   cgm-display.ota.bin       app only, for the device's own update check
#
# and writes docs/manifest.json describing both, which GitHub Pages serves.
#
#   ./make-release.sh "what changed" [ota.bin] [factory.bin]
#
# With no paths it looks in the usual ESPHome build directory. Compile first:
#
#   esphome compile cgm-display.yaml
#
# Then commit docs/ and push.
set -euo pipefail
cd "$(dirname "$0")"

NAME=cgm-display
SUMMARY="${1:-Maintenance release}"
OTA="${2:-}"
FACTORY="${3:-}"

VERSION=$(awk '/^  project:/{f=1} f&&/version:/{gsub(/[" ]/,"");sub(/version:/,"");print;exit}' "$NAME.yaml")
[ -n "$VERSION" ] || { echo "could not read project.version from $NAME.yaml"; exit 1; }

BUILD=".esphome/build/$NAME/build"
[ -n "$OTA" ]     || OTA=$(find "$BUILD" -name 'firmware.ota.bin' 2>/dev/null | head -1 || true)
[ -n "$FACTORY" ] || FACTORY=$(find "$BUILD" -name 'firmware.factory.bin' 2>/dev/null | head -1 || true)

[ -n "$OTA" ] && [ -f "$OTA" ] || {
  echo "No OTA image found. Compile first, or pass paths:"
  echo "  ./make-release.sh \"$SUMMARY\" firmware.ota.bin firmware.factory.bin"; exit 1; }

echo "version $VERSION - $SUMMARY"
mkdir -p docs
md5of() { md5 -q "$1" 2>/dev/null || md5sum "$1" | cut -d' ' -f1; }

cp "$OTA" "docs/$NAME.ota.bin"
OTA_SIZE=$(wc -c < "docs/$NAME.ota.bin" | tr -d ' ')
[ "$OTA_SIZE" -gt 100000 ] || { echo "OTA image looks truncated ($OTA_SIZE bytes)"; exit 1; }
OTA_MD5=$(md5of "docs/$NAME.ota.bin")
echo "  ota      $OTA_SIZE bytes  md5 $OTA_MD5"

PARTS=""
if [ -n "$FACTORY" ] && [ -f "$FACTORY" ]; then
  cp "$FACTORY" "docs/$NAME.factory.bin"
  F_SIZE=$(wc -c < "docs/$NAME.factory.bin" | tr -d ' ')
  [ "$F_SIZE" -gt 100000 ] || { echo "factory image looks truncated ($F_SIZE bytes)"; exit 1; }
  echo "  factory  $F_SIZE bytes"
  PARTS='
      "parts": [
        { "path": "'"$NAME"'.factory.bin", "offset": 0 }
      ],'
else
  echo "  factory  (none - browser flashing will not be offered)"
fi

cat > docs/manifest.json <<JSON
{
  "name": "CGM Display",
  "version": "$VERSION",
  "home_assistant_domain": "esphome",
  "new_install_prompt_erase": false,
  "builds": [
    {
      "chipFamily": "ESP32",$PARTS
      "ota": {
        "path": "$NAME.ota.bin",
        "md5": "$OTA_MD5",
        "summary": "$SUMMARY"
      }
    }
  ]
}
JSON
python3 -c "import json;json.load(open('docs/manifest.json'))" && echo "  manifest.json valid"
echo
echo "Next: commit docs/ and push."
