# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Autonomous BLE beacon system for local positioning of transit stops and road objects. Tags broadcast iBeacon packets where `UUID` is a static operator identifier and `Major`/`Minor` rotate every 5-minute slot via AES-128 ECB — so `TagID` is never transmitted in the clear. A server (or mobile app) recovers `TagID` by brute-forcing `tag_id × [slot-1, slot, slot+1]` against the known key.

Primary language: Russian (docs, comments, commit messages).

## Repository structure

```
firmware/          — Production C firmware for nRF52832 (YJ-16013 module)
  src/             — main.c, tag_app.c, beacon_id.c, aes128.c, tag_platform_nrf52832.c
  tag_config.example.h  — Template: TAG_ID, KEY, UUID, unix_time, night mode
  pca10040e/s112/armgcc/  — Makefile build target
prototype/         — TinyGo lab prototype on ProMicro nRF52840 (algorithm verification only)
  firmware/tinygo/
server/            — Python lookup + operator registry
  lookup.py        — Local identification and multi-operator routing
  keygen.py        — AES-128 region key generator
  operators.example.json — Operator registry format
  lookup-pwa/      — Browser-based offline locator (PWA)
mobile/t1_ble_scanner/  — Flutter Android app (offline AES-128 decryption)
  lib/src/
    services/ble_scanner_controller.dart  — BLE scan + decryption pipeline
    services/t1_crypto.dart               — AES-128 ECB with precomputed round keys
    services/stops_repository.dart        — SharedPreferences CRUD for stop names
    services/operators_repository.dart    — SharedPreferences CRUD for operator registry
    models/app_config.dart                — App config loaded from assets/config/app_config.json
    ui/                                   — scanner_page, radar_view, editors, settings_sheet
  assets/config/app_config.json  — Default UUID, operators, stops, AES key
docs/              — Algorithm, architecture, protocol, battery, BOM specs
manufacturing/     — Production checklist and flash scripts
configuration/     — (region-specific configs, not committed with real keys)
```

## Commands

### Firmware (nRF5 SDK 17.1.x + SoftDevice S112)

```bash
cd firmware/pca10040e/s112/armgcc
make                    # build application
make flash_softdevice   # flash S112 SoftDevice first
make flash              # flash application
```

Config: copy `firmware/tag_config.example.h` to `firmware/src/tag_config.h` and fill in `TAG_ID`, `TAG_KEY`, `TAG_IBEACON_UUID`, `TAG_INITIAL_UNIX_TIME`. **Never commit `tag_config.h` with a real key.**

**Flashing via RP2040 (no J-Link)** — flash RP2040 with `debugprobe_on_pico.uf2`, wire GPIO2→SWDCLK / GPIO3→SWDIO / GND→GND / 3V3→VDD, then use pyOCD:
```powershell
# Use Python 3.12 x64 explicitly — pyocd fails on Python 3.14 ARM64
C:\Python312x64\Scripts\pyocd.exe erase -t nrf52832 -f 5000 --chip
C:\Python312x64\Scripts\pyocd.exe flash -t nrf52832 -f 5000 s112_nrf52_7.2.0_softdevice.hex
C:\Python312x64\Scripts\pyocd.exe flash -t nrf52832 -f 5000 _build\nrf52810_xxaa.hex
C:\Python312x64\Scripts\pyocd.exe reset -t nrf52832 -f 5000
```
Full guide: `docs/nrf5-sdk-swd-setup.md` → section "Альтернативный программатор: RP2040".

**CRITICAL — SWD frequency**: use `-f 5000` (5 kHz), NOT 100 kHz — 100 kHz causes "Unexpected ACK '0'" errors with this board.

### Prototype (TinyGo on ProMicro nRF52840)

```bash
cd prototype/firmware/tinygo
go mod tidy
tinygo build -o firmware.uf2 -target=nicenano .
# Then double-tap RESET to enter bootloader, copy firmware.uf2 to the USB disk
```

### Server (Python)

```bash
# Generate a region key
python server/keygen.py --region "moscow-north" --num-tags 500

# Simulate a tag packet (for testing)
python server/lookup.py --simulate --tag-id 42 \
  --key 2B7E151628AED2A6ABF7158809CF4F3C

# Identify a tag locally
python server/lookup.py \
  --uuid FDA50693-A4E2-4FB1-AFCF-C6EB07647825 \
  --major 20CD --minor F4A0 \
  --key 2B7E151628AED2A6ABF7158809CF4F3C \
  --num-tags 500
```

### Mobile app (Flutter)

```bash
cd mobile/t1_ble_scanner
flutter pub get
flutter analyze                        # must show: No issues found
flutter run -d <device_id> --release   # Flutter 3.41.8, Dart 3.11.5
flutter build apk --release            # build APK only
```

**Note**: Android SDK is NOT installed locally. Releases are built via CI (`.github/workflows/build-apk.yml`) triggered by `git tag v*`. To run on a connected phone without local SDK, download the APK from the GitHub release and install via MTP/USB or send the link to the phone.

**Releases**: https://github.com/sayr777/dynamic-iBeacon/releases — CI builds APK on every `v*` tag push.

## Core algorithm

```
slot  = unix_time / 300          # 5-minute window
block = tag_id[2] || slot[4] || 0x00[10]
out   = AES-128-ECB(KEY, block)

major = out[0:2]
minor = out[2:4]
mac   = out[4:10];  mac[0] |= 0xC0
```

Server lookup searches `tag_id × [slot-1, slot, slot+1]` to handle clock drift and delivery delay.

## Key architectural points

**Multi-operator coexistence**: `UUID` identifies the operator, not the tag. Our server handles our UUID locally; foreign UUIDs are forwarded to the operator's REST endpoint per `operators.json`.

**Offline mobile path**: `t1_crypto.dart` implements the same AES-128 ECB lookup as the server, running in a Dart isolate (`compute()`) to avoid blocking the UI. Round keys are expanded once at startup (~5–10× speedup). `notifyListeners` is debounced to 100 ms (≤10 UI rebuilds/sec).

**Legacy BNSO compatibility**: Until scanners pass `UUID + Major + Minor`, two legacy ID schemes are supported — Umka (`Major*65536 + Minor`) and Scout (`Major + Minor`).

**Production security**: `APPROTECT` must be enabled before shipping. `KEY` is flashed at production and never stored in source control. `tag_config.h` is gitignored.

**Night mode**: Tag increases wake interval from 2 s to 60 s between configurable local-time hours; `Major/Minor` still rotate on the 5-min slot boundary (driven by `unix_time`, not the wake counter).

## Mobile app UI (v1.3.3)

App name: **T1 BLE Control**

- **Toggle button in AppBar**: "T1 BLE Control" is a tap button. Active = blue border + spinner; inactive = grey. Tapping while active calls `stopScan()` + `clearDevices()`. Tapping while inactive calls `startScan()`.
- **RadarView**: accepts `scanning: bool`. When false — animation stops (`_ctrl.stop()`), sweep resets to 0.
- **BeaconViewModel**: `lastInterval` (Duration?) = time between two last packets; `isActive` getter = `lastSeen` < 30 s ago.
- **Device cards**: show `_ActivityBadge` (green "Активна" / red "Нет сигнала") and "Интервал посылки" row.
- **Auto-remove**: devices absent > 1 minute removed by `_cleanupTimer` (Timer.periodic 30 s).

### flutter_blue_plus `result.timeStamp` behaviour (IMPORTANT)

In flutter_blue_plus v1.36.x, `ScanResult.timeStamp = DateTime.now()` is set in `fromProto()` the moment Flutter receives the native BLE callback for that specific device. The `scanResults` stream emits the FULL cached list on every packet — but only the device that actually sent a packet gets a new `ScanResult` object (fresh `timeStamp`). Other devices in the batch retain their OLD `ScanResult` with OLD timestamps.

Consequence: `rawTs != prevRawTs` (exact equality check) reliably detects genuine new packets per device. A `> 50ms` threshold is too coarse — it breaks for devices advertising ≤ 50ms.

T1 key-change artefact: when `ib:UUID:major:minor` resolves to `t1:tagId`, `_rawTimestamps` must be transferred from the old key to the new key, otherwise the first post-resolution batch produces `interval = rawTs - existing.lastSeen ≈ 0ms`.

**CRITICAL**: `continuousUpdates: true` is required in `startScan`. Without it, Android deduplicates identical BLE packets — the T1 tag sends the same `major:minor` for the entire 5-minute slot, so Android only delivers the first packet. `rawTs` freezes → `isActive = false` after 30 s. With `continuousUpdates: true`, Android delivers every packet (including duplicates).

**CRITICAL**: `removeIfGone: Duration(minutes: 1)` is required alongside `continuousUpdates`. Without it, flutter_blue_plus's internal `output` cache retains stale devices forever. After `_cleanupStaleDevices` removes a device from `_devices`, the next batch re-adds it from `output` → endless oscillation every 30 s.

### Unit tests

```bash
cd mobile/t1_ble_scanner
flutter test   # 15 tests in test/models/beacon_view_model_test.dart
```

## app_config.json structure

```json
{
  "local":    { "uuid": "FDA50693-...", "name": "T1", "code": "T1" },
  "external": [{ "uuid": "...", "name": "Оператор", "code": "OPR" }],
  "stops":    { "50": "Парк Победы" },
  "defaults": {
    "keyHex": "2B7E...",
    "tagMax": 100,
    "productionSlotWindow": 5,
    "prototypeSlotMax": 2000
  }
}
```

## Firmware bugs (confirmed, fixes partially applied)

Three root causes why YJ-16013 tag is not visible after flash (confirmed via pyocd SWD debugging):

1. **GPREGRET2 is 8-bit hardware** — `tag_platform_get/set_unix_time()` must use both GPREGRET (hi byte) + GPREGRET2 (lo byte) of a 16-bit delta from `TAG_INITIAL_UNIX_TIME`.
2. **`sd_power_system_off()` returns error 0x2006 when SWD connected** — must ignore error and fall back to `NRF_POWER->SYSTEMOFF = 1`.
3. **`last_slot` initialized to 0 on first boot** — must use `(uint32_t)-1U` to force UPDATE_PARAMS on first cycle.

See memory file `project_tag_invisible_bugs.md` for full details and fix code.
