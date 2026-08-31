# Firmware update channel

GitHub Pages serves this folder at
`https://erikpendragon.github.io/nightscout-tdisplay/`, which is the URL
compiled into `cgm-display.yaml` as `fw_manifest`.

**To enable:** repo Settings → Pages → Source: *Deploy from a branch* →
branch `main`, folder `/docs`.

**To cut a release:**

1. Bump `project.version` in `cgm-display.yaml` (the device compares this
   against the manifest as a plain string — any difference offers an update).
2. Compile in the Home Assistant ESPHome add-on.
3. Run `./make-release.sh "what changed"` from the repo root.
4. Commit and push `docs/`.

Devices check every 6 hours, or on demand from the device's own web page.
The device never installs unattended — the update is always offered, never
applied.
