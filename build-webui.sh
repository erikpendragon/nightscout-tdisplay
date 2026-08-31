#!/bin/bash
# Nightscout T-Display - a standalone Nightscout glucose display
# Copyright (C) 2026 erikpendragon
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See LICENSE, and NOTICE for the ESPHome relationship.
#
# Distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY -
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. NOT A MEDICAL DEVICE.

# Builds web-ui.js = ESPHome's own web UI bundle + cgm-ui.js.
#
# Why: the config page has to work with no internet. ESPHome's `local: true`
# would do that, but it silently disables js_include (it serves a prebuilt
# INDEX_GZ and never uses the index that carries the <script src=/0.js> tag),
# so the UI tweaks in cgm-ui.js stop running. Concatenating instead gives both:
# one request, to the device, containing everything.
#
# Needs internet to BUILD. The device then needs none to RUN.
set -euo pipefail
cd "$(dirname "$0")"

SRC="${1:-https://oi.esphome.io/v3/www.js}"
OUT=web-ui.js

echo "fetching $SRC"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
curl -fsSL --compressed -o "$TMP" "$SRC"

grep -q "esp-entity-table" "$TMP" \
  || { echo "that does not look like the ESPHome UI bundle"; exit 1; }

{
  echo "// ---------------------------------------------------------------------"
  echo "// GENERATED - do not edit. Rebuild with ./build-webui.sh"
  echo "// ESPHome's web UI bundle, then cgm-ui.js. Served from the device as"
  echo "// /0.js so the config page needs no internet."
  echo "// source: $SRC"
  echo "// ---------------------------------------------------------------------"
  cat "$TMP"
  echo ""
  echo "// ------------------------- cgm-ui.js ---------------------------------"
  cat cgm-ui.js
} > "$OUT"

echo "wrote $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
echo "now: copy web-ui.js and cgm-display.yaml to the ESPHome config dir, then compile."
