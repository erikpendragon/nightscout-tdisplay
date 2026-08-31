# Nightscout T-Display

A standalone glucose display for a **LilyGO T-Display** (ESP32, 135×240 colour
LCD, about $12). It reads a Nightscout site directly over HTTP and shows the
current value, trend, recent history, treatments and time-in-range on a little
screen you can leave on a desk or nightstand.

No Home Assistant, no MQTT, no broker, no cloud account, no phone app open in
the background. Wifi and a Nightscout URL, and it works.

> ## This is not a medical device
>
> Every number on this screen is already several minutes old before it
> arrives — CGM readings lag blood, Nightscout lags the CGM, and this device
> polls on top of that. **Do not dose from it.**
>
> There are deliberately **no alarms**. It will not wake anyone up, and it must
> never be the thing standing between someone and a hypo. Keep your real
> alarms where they belong: in Dexcom Follow, xDrip, or Nightscout's own
> alarms. This is a passive, at-a-glance display and nothing more.

---

## What it shows

Seven pages, plus one that only exists when the data has gone stale. The top
button moves forward, the bottom button moves back, **both together flip the
screen 180°** (for when the USB cable has to come out the other side), and
after a configurable idle time it returns to the main page.

| Page | Contents |
|---|---|
| **Main** | Current value, trend arrow, last delta, reading age. Whole-screen colour band. |
| **Graph** | Configurable 1–24 h, labelled Y axis, all four threshold lines. |
| **Treatments** | Last three carb/insulin entries with ages, plus 24 h totals. |
| **Stats** | Time in range / low / high as percentages, min / max / average, feed coverage. |
| **Diagnostics** | IP, wifi RSSI, uptime, free heap, detected units. |
| **Wear time** | Pod, sensor and reservoir: time used, **time left**, coloured as each nears its life. |
| **Recent alerts** | Last 5 pump/CGM alarms with how long ago, tagged `DEV` or `BG`. |

The main page is readable across a room: the background is the colour band, so
"is it fine?" is answerable from the doorway without reading a digit.

Colour is never the only signal — bands, treatment columns and stale state all
carry a word or a label as well.

### Trend arrows

Every value Nightscout's `direction.js` can produce is drawn, not just the
common seven. The rate bands below are Dexcom's; other uploaders set the same
strings from their own maths.

| Nightscout `direction` | On screen | Rate | Meaning |
|---|---|---|---|
| `TripleUp` | three arrows up | — | Only from xDrip/Libre uploaders, never Dexcom Share |
| `DoubleUp` | two arrows up | > 3 mg/dL/min (> 0.17 mmol) | Rising fast — roughly +2.5 mmol/L in 15 min |
| `SingleUp` | one arrow up | 2–3 mg/dL/min | Rising |
| `FortyFiveUp` | arrow up 45° | 1–2 mg/dL/min | Rising slowly |
| `Flat` | arrow right | < 1 mg/dL/min either way | Steady |
| `FortyFiveDown` | arrow down 45° | 1–2 mg/dL/min | Falling slowly |
| `SingleDown` | one arrow down | 2–3 mg/dL/min | Falling |
| `DoubleDown` | two arrows down | > 3 mg/dL/min | Falling fast |
| `TripleDown` | three arrows down | — | As TripleUp |
| `RATE OUT OF RANGE` | double-headed arrow + **FAST** | — | Changing faster than the sensor will put a number on |
| `NOT COMPUTABLE` | **NO TREND** | — | Not enough history yet — new sensor, or a gap in the feed |
| `NONE` | **NO TREND** | — | No direction supplied |

A trend the firmware does not recognise falls back to `?` rather than being
silently dropped.

### Stale data is loud

If a reading is older than your "Stale After" setting, the whole display drops
to greyscale — black background, white labels, grey numbers. Colour on this
screen means "this is current", so when nothing is current, nothing is
coloured. The status strip along the bottom reads **STALE FOR 25 MIN**.

An extra **STALE DATA** page appears at the front of the rotation saying how
long it has been. The reading itself is still there, one button press away and
struck through — the same convention Nightscout uses for looking at the past.
A number that might be an hour old is worse than no number at all, so it is
never presented as if it were live.

**NO DATA** is a different screen, shown only when the device has never
received a reading at all — usually a wrong URL, and it tells you where to go
to fix it.

### The web page hides what it is not using

The device serves its own web UI — ESPHome's bundle with `cgm-ui.js` appended,
assembled by `build-webui.sh`. That script watches two switches: it locks the
four manual threshold fields whenever **Use Nightscout Thresholds** is driving
them, and hides **Reservoir life** unless **Separate Reservoir** is on. Fields
you are not using stay out of the way.

Serving the bundle from the device rather than a CDN is deliberate: the config
page is what you reach for when something is wrong, and it has to work on a
network with no internet. (ESPHome's `local: true` looks like the way to do
that, but it silently disables `js_include` — hence the assembled file.)

ESPHome has no runtime show/hide of its own, so this reaches into the v3 UI's
shadow DOM, which is **not a documented API**. It fails quietly: if a future
ESPHome restructures that UI, the rows simply stay visible.

### Pod and sensor age, with nobody logging anything

If your pump data reaches Nightscout through Glooko, the **Wear time** page
fills itself in. Glooko records `pod_activating`, `reservoir_change` and
`cgm_sensor_change` from the pump's own event log, so the counters reset at the
moment the pod actually changed — not when somebody remembered to write it
down, and not on a recurring calendar reminder that goes wrong the first time
something is changed early.

There is a catch: **stock nightscout-connect never fetches those events.** It
requests only basals, boluses and CGM readings, and its converter only emits
`Meal Bolus` and `Temp Basal`. Two changes to `lib/sources/glooko/` fix it —
add `/api/v2/pumps/events` to the fetch (with its **own** query window; the
shared one pins `lastUpdatedAt` to now and collapses `limit` to nothing), and
map the event types to `Site Change`, `Insulin Change` and `Sensor Start`.

A patched fork is at
[erikpendragon/nightscout-connect](https://github.com/erikpendragon/nightscout-connect)
if you would rather run it than apply the changes yourself.

Without that patch this page simply shows `--`, and everything else works
normally.

Lifetimes are set on the device's web page — 72 h for an Omnipod and 264 h for
a Dexcom G7 by default. Glooko does not publish an expiry time, so "time left"
is the start event plus the nominal life, which is what the pump itself counts
down. Set them to whatever your own kit actually runs.

On an Omnipod the reservoir lives inside the pod, so both are replaced in the
same action and the reservoir row is folded into the pod one. If you use a
tubed pump, where the cartridge and the infusion site change independently,
turn on **Separate Reservoir** and it becomes its own row.

### Pump and CGM alarms

Glooko records every alarm the pump and sensor raised — `/api/v2/pumps/alarms`.
`alarm_type` is always null; the machine-readable code lives in **`value`**:

| Device health | Glucose thresholds |
|---|---|
| `omnipod_exit_close_loop` | `dexcom_low_glucose_alert` |
| `omnipod_twelve_missing_egv` | `dexcom_high_glucose_alert` |
| `omnipod_low_reservoir` | `dexcom_urgent_low_alert` |
| `omnipod_pod_expiration*`, `omnipod_pump_expired` | `dexcom_urgent_low_soon` |
| `dexcom_signal_loss`, `dexcom_brief_sensor_issue` | `dexcom_*_fast_alert` |

The bridge patch imports them as **`Note`** treatments — deliberately not
`Announcement`, which Nightscout escalates into notifications. They appear as
markers on the Nightscout graph and on the device's alerts page, and nothing
beeps. The device-health ones matter most: nothing else surfaces them, and
Dexcom Follow will never tell you the pump dropped out of automated mode.

> These are **past events**. The feed records that an alarm fired; it never
> says one cleared. The page is worded in the past tense for that reason —
> "Sensor signal lost, 40 min ago", never "signal is lost". Do not read it as
> live device state.

---

## Why there is no clock

The device never learns the time. There is no SNTP, no RTC, no timezone.

Nightscout tells you what time *it* thinks it is (`status[0].now`), and every
reading and treatment carries a UTC timestamp. So the device stores the age of
a reading at the moment it fetched it, and adds its own `millis()` since. That
gives an accurate age with no clock, no drift and no DST — and it keeps working
if NTP is blocked, which on a locked-down IoT VLAN it often is.

The trade-off is that ages are only as good as your Nightscout server's clock.
That is fine; it is the same clock that stamped the data.

---

## Hardware

- **LilyGO T-Display** — ESP32-D0WDQ6-V3, ST7789V 135×240 IPS.
  The common 16 MB variant with the CH9102 USB serial chip.
- A USB-C cable.

That is the entire bill of materials. Nothing to solder, no wiring diagram.

> **GPIO4 is the backlight** and is claimed by the `TTGO_TDISPLAY_135X240`
> preset. Declaring your own output on it is a **fatal** config error, not a
> warning. This is why there is no brightness control.

---

## Install

Two ways in. The first needs nothing but a USB cable.

### 1. Flash the pre-built firmware

Every release publishes a complete image — bootloader, partition table and
app — so a blank board needs no build tools at all.

Download
[`cgm-display.factory.bin`](https://erikpendragon.github.io/nightscout-tdisplay/cgm-display.factory.bin)
and write it at offset 0:

```bash
esptool.py --chip esp32 --port /dev/ttyUSB0 write_flash 0x0 cgm-display.factory.bin
```

`pip install esptool` if you don't have it. On macOS the port is usually
`/dev/cu.usbserial-*`; on Windows a `COM*` number.

After this the device updates itself — it checks the manifest every six hours
and offers new versions on its own web page. You never need to touch a cable
again.

### 2. Build it yourself with ESPHome

Worth doing if you want to change anything. You need
[ESPHome](https://esphome.io) — **the CLI on its own is enough**:

```bash
pip install esphome
git clone https://github.com/erikpendragon/nightscout-tdisplay
cd nightscout-tdisplay
./build-webui.sh                 # bundles the web UI so it works offline
esphome run cgm-display.yaml     # USB the first time
```

Home Assistant is *not* required. If you happen to run the ESPHome add-on you
can use it, but it only ever *builds* the firmware — the device never talks to
Home Assistant, and nothing here depends on it.

Updates afterwards are over the air:

```bash
esphome upload cgm-display.yaml --device <device-ip>
```

`--device` is required for OTA; without it ESPHome goes looking for a serial
port.

If you use **mg/dL**, swap the units block at the top of `cgm-display.yaml` —
the mg/dL values are there, commented out. The display detects mg/dL vs mmol/L
from Nightscout by itself; the block only sets sensible ranges for the
threshold fields.

### About credentials

There is no `secrets.yaml` to fill in. **The config and the compiled firmware
contain no credentials of any kind** — not wifi, not an API key, not an OTA
password. Everything the device needs is entered on the device itself and
lives in its flash, never in the image. So the published binary is safe for
anyone to download, and an update can never carry somebody else's wifi
password into your device.

> **A configured board is a different matter.** Once you have set it up, its
> flash holds your wifi credentials, your Nightscout URL and your token — and
> flash can be read back over USB by anyone holding the board. Treat a
> configured device like a phone, not like a cable.
>
> Before giving one away, press **Factory Reset** on its web page. That clears
> the wifi credentials, the URL, the token and every stored setting, and the
> board comes back up as the `CGM Display Setup` access point. If you would
> rather not trust a button with it, `esptool.py erase_flash` followed by a
> fresh factory image leaves nothing behind at all.

The remaining trade is that anyone already on your LAN can reflash the board
and open its web page. For a $12 display on a home network that is the usual
bargain; if you would rather not, the config has commented blocks showing
where to add an API encryption key and an OTA password.

---

## First run

1. The board comes up as a wifi access point called **CGM Display Setup**.
   Join it and enter your wifi credentials. They are saved to the device's
   flash, not to the firmware.
2. It reboots onto your network and shows a **SETUP** screen with its own IP.
3. Browse to `http://<that-ip>` — or `http://cgm-display.local` if your
   network resolves mDNS and you kept the default name — and fill in:

The settings are grouped the way you meet them.

**Nightscout**

| Field | Notes |
|---|---|
| **Nightscout URL** | `http://nightscout.example.com` or `http://192.168.1.50:1337`. No trailing slash needed. |
| **Token** | Only if your site needs auth. A **read-only** token is plenty — this device never writes. Leave blank for an open instance. |
| **Use Nightscout Thresholds** | On by default. Pulls your four thresholds from the site itself, so there is one set of numbers rather than two that can disagree. Turn it off to type your own. |

**Blood glucose thresholds** — only editable with the switch above off.
**Use your own care team's numbers.** Every percentage on the device is
measured against them.

**Display**

| Field | Notes |
|---|---|
| **Graph Hours** | 1–24. |
| **Stale After** | Minutes before the display goes greyscale and says STALE. 15 is a reasonable start. |
| **Idle Return** | Seconds of no button input before it returns to the main page. Default 15. |
| **Flip Screen** | Rotates 180°, for when the USB cable has to come out the other side. |

**Hardware Replacement**

| Field | Notes |
|---|---|
| **Sensor / Pod life (hours)** | Defaults are a G7 at 264 h and an Omnipod at 72 h. Set them to what your own kit runs. |
| **Separate Reservoir** | Off by default — on an Omnipod the reservoir is inside the pod. Turn on for a tubed pump, and **Reservoir life** appears. |
| **Warning / Urgent at % left** | When the wear-time bars turn amber and red. |

All of it — wifi included — is stored in the device's flash, **not** in the
firmware. It survives reboots and it survives firmware updates. You type it
once. You can also hand someone a pre-flashed board and they can point it at
their own Nightscout without ever installing ESPHome.

> One gotcha worth knowing if you edit the config: the `initial_value:` fields
> are only compile-time defaults. They are read at boot and never written to
> flash. A setting is only stored once you actually change it from the web
> page — after which the default is ignored forever.

---

## Updating

The device carries a **Firmware** update entity. Every 6 hours it fetches a
manifest from the URL in `fw_manifest:` at the top of the config, compares the
version, and offers the update on its own web page (and in Home Assistant, if
you use it). It never installs unattended — you press the button.

Updating replaces only the application. Your wifi, Nightscout URL, token and
thresholds live in a separate flash area and are untouched — which is also why
an update can never carry one person's settings onto another person's device.

### Publishing your own builds

`./make-release.sh "what changed"` does all of this: it copies both images
into `docs/`, computes the MD5 and writes the manifest. Commit `docs/` and
push — GitHub Pages serves it, and devices pointed at your fork pick it up on
their next check.

By hand, host these files together anywhere that serves plain HTTP(S):

```json
{
  "name": "CGM Display",
  "version": "1.1.0",
  "builds": [
    {
      "chipFamily": "ESP32",
      "parts": [
        { "path": "cgm-display.factory.bin", "offset": 0 }
      ],
      "ota": {
        "path": "cgm-display.ota.bin",
        "md5": "<md5sum of that file>",
        "summary": "What changed"
      }
    }
  ]
}
```

`path` is resolved relative to the manifest URL. Both images come out of
`esphome compile` under `.esphome/build/cgm-display/build/` — `firmware.ota.bin`
is the app alone, for devices already running this firmware, and
`firmware.factory.bin` is the complete image for a blank board. The `parts`
block is what browser-based ESP flashers read; `ota` is what the device's own
update check reads.

> ### Set the thresholds properly
> They are placeholders out of the box. Every percentage the device
> reports — time in range, low, high — is measured against them, and so are
> all the colour bands and graph lines. Wrong thresholds do not produce a
> slightly-off display, they produce confidently wrong statistics.

---

## What it asks Nightscout for

Read-only, four endpoints, polled gently:

| What | Endpoint | Every |
|---|---|---|
| Current value | `/pebble` | 60 s |
| Graph history | `/pebble?count=<hours×12>` | 5 min |
| Stats | `/pebble?count=288` | 5 min |
| Treatments | `/api/v1/treatments.json?count=12` | 5 min |

`/pebble` is used rather than `/api/v1/entries.json` because it is around 3.5×
smaller, already converted to your display units, and a JSON object rather than
a top-level array — all three matter on a device with a few hundred KB of heap.

Your Nightscout needs to allow reads. Either set `AUTH_DEFAULT_ROLES=readable`,
or issue a read-only token and paste it into the token field.

---

## Licence

MIT. See [LICENSE](LICENSE).

Not affiliated with Nightscout, Dexcom, Insulet or Glooko. Nightscout is a
community project; this is a small client for it.
