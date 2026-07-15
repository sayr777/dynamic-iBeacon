# SKILLS.md — Project skills and runbooks

## Mobile app: install on Android phone

### Option A — via GitHub Release (no ADB needed)
1. Open on phone: https://github.com/sayr777/dynamic-iBeacon/releases/latest
2. Download `T1_BLE_Scanner_vX.Y.Z.apk`
3. Open file → install (allow unknown sources in Settings → Security)

### Option B — via USB file transfer (MTP, no ADB)
1. Connect phone via USB → select "File Transfer / MTP" on phone
2. Copy `T1_BLE_Scanner_vX.Y.Z.apk` (on Desktop after CI download) to phone Downloads
3. On phone: open file manager → Downloads → tap APK → install

### Option C — via ADB (requires Android SDK platform-tools)
```powershell
# Install platform-tools only (no full Android Studio needed):
# Download from https://developer.android.com/tools/releases/platform-tools
# Extract to C:\android-platform-tools\ and add to PATH

adb devices                                      # verify phone is listed as "device"
adb install C:\Users\sayr\Desktop\T1_BLE_Scanner_v1.3.0.apk
```

## Mobile app: run in debug mode (requires Android SDK)

```powershell
# 1. Install Android Studio and let it install Android SDK
# 2. Set SDK path:
flutter config --android-sdk "C:\Users\sayr\AppData\Local\Android\Sdk"

# 3. Enable USB debugging on phone (Settings → Developer options)
# 4. Run:
cd mobile/t1_ble_scanner
flutter devices          # confirm phone appears
flutter run -d <id>      # hot-reload debug session
```

## Firmware: build and flash

```powershell
# Build
cd C:\nRF5\work\ble-tag-jdy23\pca10040e\s112\armgcc
make

# Flash (SoftDevice already on device — skip erase)
C:\Python312x64\Scripts\pyocd.exe flash -t nrf52832 -f 5000 _build\nrf52810_xxaa.hex
C:\Python312x64\Scripts\pyocd.exe reset -t nrf52832 -f 5000

# Full chip erase + reflash (if needed)
C:\Python312x64\Scripts\pyocd.exe erase -t nrf52832 -f 5000 --chip
C:\Python312x64\Scripts\pyocd.exe flash -t nrf52832 -f 5000 "C:\nRF5\nRF5_SDK_17.1.0_ddde560\components\softdevice\s112\hex\s112_nrf52_7.2.0_softdevice.hex"
C:\Python312x64\Scripts\pyocd.exe flash -t nrf52832 -f 5000 _build\nrf52810_xxaa.hex
C:\Python312x64\Scripts\pyocd.exe reset -t nrf52832 -f 5000
```

## Firmware: SWD debug reads

```powershell
$pyocd = "C:\Python312x64\Scripts\pyocd.exe"
# Halt CPU and read PC
& $pyocd cmd -t nrf52832 -f 5000 -c "halt" -c "reg pc"
# Read retention registers (8-bit each)
& $pyocd cmd -t nrf52832 -f 5000 -c "read32 0x4000051C" -c "read32 0x40000520"
# Read RESETREAS (bit4=OFF wake, bit0=reset pin)
& $pyocd cmd -t nrf52832 -f 5000 -c "read32 0x40000400"
# Read RADIO STATE (0=disabled, 11=TX)
& $pyocd cmd -t nrf52832 -f 5000 -c "read32 0x40001000"
```

## Release: publish new version

```powershell
# 1. Edit code
# 2. Bump pubspec.yaml version (e.g. 1.3.0+7 → 1.4.0+8)
# 3. Update release notes in .github/workflows/build-apk.yml
# 4. Stage only mobile files:
git add mobile/t1_ble_scanner/pubspec.yaml `
        mobile/t1_ble_scanner/lib/... `
        .github/workflows/build-apk.yml
git commit -m "feat(mobile): vX.Y.Z — description"
git push origin <branch>
git tag vX.Y.Z
git push origin vX.Y.Z
# CI builds APK and creates GitHub Release automatically (~6 min)
```

## flutter analyze

```powershell
cd mobile/t1_ble_scanner
flutter analyze   # must show: No issues found
```
