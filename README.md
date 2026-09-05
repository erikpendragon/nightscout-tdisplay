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

If **Brightness** is set to 0 the screen is off, and the first press of either
button only wakes it — at **Wake Brightness**, on the main page, for one
**Idle Return**. Cycle pages from there if you want; when it times out back to
the main page it goes dark again. On a display that is merely dim, buttons
never change the brightness at all.

| Page | Contents |
|---|---|
| **Main** | Current value, trend arrow, last delta, reading age. Whole-screen colour band. |
| **Graph** | Configurable 1–24 h, labelled Y axis, all four threshold lines. |
| **Treatments** | Last three carb/insulin entries with ages, insulin and carbs still on board, and 24 h totals. |
| **Stats** | Time in range / low / high as percentages, min / max / average, feed coverage. |
| **Diagnostics** | IP, wifi RSSI, uptime, free heap, detected units, installed firmware — and **UPDATE AVAILABLE** in red when there is one. |
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
assembled by `build-webui.sh`. `cgm-ui.js` watches two switches: it locks the
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

> **GPIO4 is the backlight**, and the `TTGO_TDISPLAY_135X240` preset claims it
> as a plain on/off pin. While it does, declaring your own output on GPIO4 is a
> **fatal** config error, not a warning — so the pin has to be handed over
> rather than shared. `backlight_pin: false` on the display makes the preset let
> go of it, which frees an `ledc` channel to drive the same pin as PWM. That is
> what **Brightness** is.

---

## Install

Two ways in. The first needs nothing but a USB cable.

### 1. Flash the pre-built firmware

Every release publishes a complete image — bootloader, partition table and
app — so a blank board needs no build tools at all.

Download `cgm-display.factory.bin` from the
[latest release](https://github.com/erikpendragon/nightscout-tdisplay/releases/latest)
and write it at offset 0:

```bash
esptool.py --chip esp32 --port /dev/ttyUSB0 write_flash 0x0 cgm-display.factory.bin
```

`pip install esptool` if you don't have it. On macOS the port is usually
`/dev/cu.usbserial-*`; on Windows a `COM*` number.

After this the device updates itself — it checks the manifest every six hours
and offers new versions on its own web page. You never need to touch a cable
again.

### 2. Follow this repo from your own ESPHome

If you already run ESPHome, you do not need a copy of the config at all —
point at this repo and it stays current:

```yaml
packages:
  nightscout_tdisplay:
    url: https://github.com/erikpendragon/nightscout-tdisplay
    ref: main
    files: [cgm-display.yaml]
    refresh: 1d
```

Two support files must sit next to that stub, because ESPHome resolves
`includes:` and `js_include:` relative to your config directory rather than
the downloaded package: copy `version_compare.h` from this repo, and generate
`web-ui.js` with `./build-webui.sh`.

The published config carries no credentials, so both of the following are
optional — without them the device still works, it just has no OTA password
and an unencrypted API.

```yaml
# ota: is a LIST - lists are APPENDED, so !extend modifies the existing
# platform instead of adding a second one
ota:
  - id: !extend ota_esphome
    password: !secret my_ota_password

# api: is a MAPPING - mappings are MERGED, so no !extend, and the package's
# own api settings survive
api:
  encryption:
    key: !secret my_api_key
```

That list-versus-mapping distinction is the only fiddly part, and getting it
wrong fails in different ways: a duplicated OTA platform, or a clobbered api
block.

**To change what is compiled in**, add a `substitutions:` block. Yours override
the project's, and you list only what you want changed:

```yaml
substitutions:
  device_name: kitchen-cgm        # hostname and mDNS: kitchen-cgm.local
  friendly_name: Kitchen CGM
```

Nothing on the device's web page needs to be here — Nightscout URL, token,
thresholds, brightness and lifetimes are all stored on the device and survive
updates. Substitutions are for the handful of things that cannot be, and
`device_name` is the one with a sting: there is no runtime setter, so changing
it later means a reflash **and** Home Assistant treats the board as a new
device, leaving the old entities behind.

For **mg/dL**, switch the whole block together — the threshold sliders take
their ranges at compile time, so changing the units alone leaves sliders that
cannot reach your numbers. `example-local.yaml` has the full set ready to
uncomment.

Do **not** set `local_build` yourself. It defaults to `true`, and that is what
stops a published image being installed over the top and discarding everything
above — see [If you build your own firmware](#if-you-build-your-own-firmware).

Consider `refresh: always` rather than `1d`: ESPHome otherwise re-fetches only
when its cached copy is a day old, so a build shortly after an upstream change
quietly uses the stale copy and produces the previous version with no error.

[`example-local.yaml`](example-local.yaml) is the whole thing ready to copy.

### 3. Build it yourself with ESPHome

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
| **Brightness** | 0–100 %, straight onto the backlight PWM. Default 100. **0 is off** — see below. |
| **Wake Brightness** | 1–100 %, default 30. The level a button press wakes the screen to while **Brightness** is 0. Does nothing otherwise. |
| **Full Brightness Out Of Range** | **On by default.** The screen ignores **Brightness** and goes to full whenever the reading is not in range — see below. Turn it off and it stays off. |

**A display set to 0 is off, not lost.** Two things bring it back without the
web page:

- **Power-up.** It comes up at full brightness and stays there until the first
  reading lands, so a board joining wifi never looks dead. Then it goes dark.
  (If no reading arrives at all it gives up after 90 seconds and goes dark
  anyway, rather than sitting lit all night.)
- **Either button.** Wakes at **Wake Brightness** for one **Idle Return**, then
  back to dark.

A display set to something dim gets neither: it boots straight to its own level
and stays there, and pressing buttons only changes pages. Brightness changes
when you change it, and at no other time.

### No news is good news

Turn on **Full Brightness Out Of Range** and the display stops being a readout
and becomes a signal. While the reading is in range — the green band — the
screen does whatever **Brightness** says, including being off. The moment it is
not in range, the backlight goes to **full**, and stays there until the reading
comes back. Dark means fine; lit means go and look.

**Full means full, whatever Brightness says.** The override does not scale your
setting or only apply when the screen is off — Brightness 0, 8, 40 or 100 all
go to 100% while the reading is out of range. That is the point: the brightness
*is* the signal, so it has to be the same every time, or a low on a dimmed
display would look much like a normal reading.

Set alongside **Brightness 0** it gives you a display that is simply dark all
day and lights the room when something needs attention.

**Stale counts as not in range, deliberately.** If a device that had silently
stopped receiving looked exactly like one reporting a good number, then a dark
screen would mean either "fine" or "dead" and you could not tell which — which
would make the whole arrangement worse than useless. Dark has to be able to
mean "I checked, and it is fine". So a stale feed lights the screen too.

> This is still **not an alarm**. It lights a screen. It makes no sound, it
> will not wake anyone, and it must not be the thing standing between someone
> and a hypo. Keep your real alarms in Dexcom Follow, xDrip, or Nightscout.

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

> **Give it a minute before you unplug.** A setting takes effect the instant you
> change it, but it is only queued in memory — ESPHome writes queued settings to
> flash once a minute (`flash_write_interval`, default 60s), to spare the chip.
> Pull the power inside that window and the change is lost, silently, and the
> device comes back with the previous value. A clean reboot or an OTA flushes
> the queue first; yanking the cable does not.
>
> This is easiest to trip over with **Brightness**, because testing it tends to
> involve power-cycling. Set it, count to sixty, then unplug.

---

## Updating

Every 6 hours the device fetches a manifest from the URL in `fw_manifest:` at
the top of the config and compares it with what is installed. Its web page
shows four things under **Updates**:

| | |
|---|---|
| **Installed Version** | what is running right now |
| **Update Status** | `Up to date`, `Update available: 1.1.0`, or why a check failed |
| **Check for Updates** | asks now, rather than waiting up to six hours |
| **Install Update** | downloads and reboots — nothing happens until you press it |

Checking and installing are deliberately separate, and a press with nothing
waiting does nothing. The diagnostics page also shows **UPDATE AVAILABLE** in
red, so you do not have to open the web page to find out.

Updating replaces only the application. Your wifi, Nightscout URL, token and
thresholds live in a separate flash area and are untouched — which is also why
an update can never carry one person's settings onto another person's device.

### Staying on a version, or going back to one

Every release also publishes its own manifest, so the device does not have to
follow the newest build:

| Point **Update Manifest URL** at | Behaviour |
|---|---|
| `…/nightscout-tdisplay/manifest.json` | follows the latest release (default) |
| `…/nightscout-tdisplay/v1.0.1/manifest.json` | pinned to 1.0.1, ignores anything newer |
| *(blank)* | updates off — the six-hourly check stops and both buttons decline |

Clearing the field really does turn updates off; **Update Status** says so, and
it stays off across reboots until you put a URL back.

Setting it to an *older* version downgrades: the device compares versions by
string equality rather than ordering, so it treats "different" as "update
available" and installs it. That is also why a pinned device stays put — the
manifest it is watching never changes.

[`docs/VERSIONS.md`](docs/VERSIONS.md) lists what is available.

### If you build your own firmware

**A device built by hand will not install a published image over itself.** It
still checks, and still tells you which version is waiting — it just refuses to
be the one that flashes it, and points you at your own ESPHome instead.

That is not caution for its own sake. Some settings live on the device and
survive anything; others are compiled into the image and die the moment a
different image lands:

| Stored on the device — survives an update | Compiled in — replaced by any image you flash |
|---|---|
| wifi, Nightscout URL, token, manifest URL | device name (hostname and mDNS) |
| every threshold, all three wear-time lifetimes | friendly name |
| graph hours, idle return, stale after | API encryption key |
| brightness, wake brightness, and all three switches | OTA password |
| | units and the threshold slider ranges |

A **factory reset clears the left column, not the right** — it wipes stored
settings and cannot touch the program image. Taking a stock update does the
opposite: it keeps your stored settings and discards everything you compiled
in. That is the trap this exists to close.

So the device carries a marker set at build time, and behaves accordingly:

| How it was built | Checks for updates | Says a version is waiting | Install Update |
|---|---|---|---|
| This project's CI | yes | yes | **installs it** |
| **Your fork's CI**, with **Update Manifest URL** pointed at your fork | yes | yes | **installs yours** |
| By hand, in your own ESPHome | yes | yes — screen reads `BUILD LOCALLY` | refuses, and says why |

A hand-built device shows `1.0.17 (local build)` as its **Installed Version**,
directly above the button that will decline, so nothing has to be inferred from
behaviour.

**The loop for a local build** is then the one you already have: your ESPHome
pulls this repo (§2 above), so when the device says a version is waiting, you
press **Install** in ESPHome and it rebuilds *that* version with your own
substitutions layered back on. You get every change and lose nothing.

**If you want your own binaries to be installable from the web page**, build
them in CI rather than by hand — fork this repo, let its workflow build them,
and point **Update Manifest URL** at your fork's channel. The line falls where
it does for a reason: a CI runner holds no secrets, so its images are safe to
publish and therefore safe to install. An image with your encryption key in it
is neither.

Clearing **Update Manifest URL** still turns updates off entirely, on any of
the three.

## What it asks Nightscout for

Read-only. Seven requests on one scheduler, ordered by how much the freshness
matters — and at most one runs per five-second tick, so two never overlap:

| What | Endpoint | Every |
|---|---|---|
| Current value, IOB and COB | `/pebble` | 30 s |
| Recent treatments | `/api/v1/treatments.json?count=12` | 60 s |
| Graph history | `/pebble?count=<hours×12>` | 2 min |
| Pod / sensor / reservoir age | `/api/v1/treatments.json` filtered to `Site Change`, `Sensor Start`, `Insulin Change` | 5 min |
| Pump and CGM alarms | `/api/v1/treatments.json` filtered to notes | 5 min |
| Stats | `/pebble?count=288` | 15 min |
| Thresholds | `/api/v1/status.json` | 30 min |

A 24-hour time-in-range does not move in five minutes; a bolus you just
entered does.

`/pebble` is used rather than `/api/v1/entries.json` because it is around 3.5×
smaller, already converted to your display units, and a JSON object rather than
a top-level array — all three matter on a device with a few hundred KB of heap.

Your Nightscout needs to allow reads. Either set `AUTH_DEFAULT_ROLES=readable`,
or issue a read-only token and paste it into the token field.

---

## Licence

**GPLv3.** See [LICENSE](LICENSE), and [NOTICE](NOTICE) for why.

Short version: the firmware images link ESPHome's C++ runtime, which is
GPLv3, so the binaries are GPLv3 whatever this repository claims. Licensing
the whole project GPLv3 makes the source and the binaries agree.

You may use, modify and redistribute this, including commercially. If you
distribute it you must pass on the complete corresponding source under the
same terms.

Not affiliated with Nightscout, Dexcom, Insulet or Glooko. Nightscout is a
community project; this is a small client for it.
