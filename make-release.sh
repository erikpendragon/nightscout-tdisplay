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

# Both images are required. A release with only an OTA image cannot be put on
# a blank board, which is the whole point of publishing one.
[ -n "$FACTORY" ] && [ -f "$FACTORY" ] || {
  echo "No factory image found - every release must ship both."
  echo "Expected $BUILD/firmware.factory.bin, or pass it as the third argument."
  exit 1; }
cp "$FACTORY" "docs/$NAME.factory.bin"
F_SIZE=$(wc -c < "docs/$NAME.factory.bin" | tr -d ' ')
[ "$F_SIZE" -gt 100000 ] || { echo "factory image looks truncated ($F_SIZE bytes)"; exit 1; }
echo "  factory  $F_SIZE bytes"
PARTS='
      "parts": [
        { "path": "'"$NAME"'.factory.bin", "offset": 0 }
      ],'

# Each release also gets its own directory. Pointing a device's "Update
# Manifest URL" at one of these pins it to that version - and because the
# component compares versions by string equality rather than ordering, an
# older one installs happily, so this is also how you downgrade.
VDIR="docs/v$VERSION"
mkdir -p "$VDIR"
cp "docs/$NAME.ota.bin" "$VDIR/"
[ -f "docs/$NAME.factory.bin" ] && cp "docs/$NAME.factory.bin" "$VDIR/"

write_manifest() {  # $1 destination
cat > "$1" <<JSON
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
}
write_manifest docs/manifest.json
write_manifest "$VDIR/manifest.json"
python3 -c "import json;json.load(open('docs/manifest.json'))" >/dev/null && echo "  manifest.json valid"
echo "  pinned copy in $VDIR/"

# Regenerate the version index so the available builds are discoverable.
{
  echo "# Available firmware versions"
  echo
  echo "The device follows \`manifest.json\` and always offers the newest build."
  echo "To pin it to a particular version - or to go back to an older one - set"
  echo "**Update Manifest URL** on the device's web page to that version's"
  echo "manifest. It will then stay there until you point it somewhere else."
  echo
  echo "| Version | Manifest URL to pin to | Full image |"
  echo "|---|---|---|"
  for d in $(ls -d docs/v*/ 2>/dev/null | sort -Vr); do
    v=$(basename "$d"); v=${v#v}
    base="https://erikpendragon.github.io/nightscout-tdisplay/v$v"
    echo "| \`$v\` | \`$base/manifest.json\` | [factory.bin]($base/$NAME.factory.bin) |"
  done
} > docs/VERSIONS.md
echo "  wrote docs/VERSIONS.md"

# Every file a manifest points at must exist AND be committable. A blanket
# *.bin rule in .gitignore silently drops these, and the failure only shows up
# as a 404 on the device hours later - so check it here instead.
echo
fail=0
for M in docs/manifest.json "$VDIR/manifest.json"; do
  DIR=$(dirname "$M")
  for REF in $(python3 -c "
import json,sys
d=json.load(open('$M'))
b=d['builds'][0]
print(b['ota']['path'])
for p in b.get('parts',[]): print(p['path'])
"); do
    if [ ! -f "$DIR/$REF" ]; then
      echo "  MISSING: $DIR/$REF (referenced by $M)"; fail=1
    elif git check-ignore -q "$DIR/$REF" 2>/dev/null; then
      echo "  IGNORED BY GIT: $DIR/$REF - it would 404 once published"
      echo "                  $(git check-ignore -v "$DIR/$REF")"; fail=1
    fi
  done
done
[ "$fail" = 0 ] && echo "  all referenced images present and committable" || exit 1
echo
cat <<NEXT
Next:

  git add -A && git commit -m "Release $VERSION: ..." && git push

then publish it on the Releases page, which is where people look for a
download (Pages only serves the update channel):

  git tag v$VERSION && git push origin v$VERSION
  gh release create v$VERSION \\
    "docs/v$VERSION/$NAME.factory.bin#$NAME.factory.bin (full image - flash a blank board)" \\
    "docs/v$VERSION/$NAME.ota.bin#$NAME.ota.bin (app only - for the device's own update)" \\
    --title "$VERSION - $SUMMARY" --notes "..."
NEXT
