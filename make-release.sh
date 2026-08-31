#!/bin/bash
# Cuts a firmware release: takes a compiled OTA binary, computes its MD5 and
# writes docs/manifest.json, which GitHub Pages serves as the update channel.
#
#   ./make-release.sh "what changed" [path/to/firmware.ota.bin]
#
# With no path it looks in the usual ESPHome build directory. Compile first:
#
#   esphome compile cgm-display.yaml
#
# Then commit docs/ and push. Devices check every 6 hours, or on demand from
# the device's own web page. They never install unattended.
set -euo pipefail
cd "$(dirname "$0")"

NAME=cgm-display
SUMMARY="${1:-Maintenance release}"
BIN="${2:-}"

VERSION=$(awk '/^  project:/{f=1} f&&/version:/{gsub(/[" ]/,"");sub(/version:/,"");print;exit}' "$NAME.yaml")
[ -n "$VERSION" ] || { echo "could not read project.version from $NAME.yaml"; exit 1; }

if [ -z "$BIN" ]; then
  BIN=$(find .esphome/build/"$NAME" -name '*.ota.bin' -o -name 'firmware.bin' 2>/dev/null | head -1 || true)
fi
[ -n "$BIN" ] && [ -f "$BIN" ] || {
  echo "No firmware found. Compile first, or pass the path:"
  echo "  ./make-release.sh \"$SUMMARY\" path/to/firmware.ota.bin"
  exit 1
}

echo "version $VERSION - $SUMMARY"
echo "  binary $BIN"
mkdir -p docs
cp "$BIN" "docs/$NAME.ota.bin"
SIZE=$(wc -c < "docs/$NAME.ota.bin" | tr -d ' ')
[ "$SIZE" -gt 100000 ] || { echo "binary looks truncated ($SIZE bytes)"; exit 1; }
MD5=$(md5 -q "docs/$NAME.ota.bin" 2>/dev/null || md5sum "docs/$NAME.ota.bin" | cut -d' ' -f1)
echo "  $SIZE bytes, md5 $MD5"

cat > docs/manifest.json <<JSON
{
  "name": "CGM Display",
  "version": "$VERSION",
  "home_assistant_domain": "esphome",
  "new_install_prompt_erase": false,
  "builds": [
    {
      "chipFamily": "ESP32",
      "ota": {
        "path": "$NAME.ota.bin",
        "md5": "$MD5",
        "summary": "$SUMMARY"
      }
    }
  ]
}
JSON
echo "  wrote docs/manifest.json"
echo
echo "Next: commit docs/ and push."
