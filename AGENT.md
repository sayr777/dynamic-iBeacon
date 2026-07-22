# AGENT.md — Agent-specific instructions

## Identity
This is the **T1 BLE beacon** project. The agent working here is `claude-sonnet-4-6` via Claude Code CLI on Windows 11 ARM64 (PowerShell primary shell).

## Language
All code comments, commit messages, docs, and communication with the user: **Russian**.

## Git
- Commits have no `Co-Authored-By` line — sole author is `sayr777` / BLE Tag Dev
- Branch: `codex/partner-service-docs` → main branch: `master`
- Release tags: `v*` → triggers CI build of APK (`.github/workflows/build-apk.yml`)

## Key tools & paths
| Tool | Path / note |
|------|-------------|
| pyocd | `C:\Python312x64\Scripts\pyocd.exe` — use x64 Python 3.12 |
| ARM GCC | `C:\Users\sayr\scoop\apps\gcc-arm-none-eabi\current\bin\` |
| nRF5 SDK | `C:\nRF5\nRF5_SDK_17.1.0_ddde560\` |
| Build dir | `C:\nRF5\work\ble-tag-jdy23\pca10040e\s112\armgcc\` |
| Flutter | in PATH, version 3.41.8 |
| Android SDK | **NOT installed locally** — APK built by CI on GitHub Actions |

## SWD frequency
Always use `-f 5000` (5 kHz) with pyocd for this board. 100 kHz causes connection errors.

## What NOT to do
- Never commit `firmware/src/tag_config.h` (contains real KEY)
- Never add Co-Authored-By to commits
- Do not run `flutter run` or `flutter build apk` locally (no Android SDK)
- Do not use `make flash_softdevice` with s112 v7.3.0 — board has v7.2.0 flashed

## flutter_blue_plus timestamp key facts
- `result.timeStamp = DateTime.now()` set in `fromProto()` on actual packet receive
- Advances ONLY for the device that sent; other devices in the batch keep old timestamp
- Detect new packets: `rawTs != prevRawTs` (exact), NOT `diff > 50ms`
- T1 key change `ib:... → t1:...`: transfer `_rawTimestamps[oldKey]` to new key in `_scheduleT1Resolution`

## Release process
1. Edit mobile code
2. Bump `mobile/t1_ble_scanner/pubspec.yaml` version
3. Update `.github/workflows/build-apk.yml` release notes
4. `git add <mobile files> pubspec.yaml .github/workflows/build-apk.yml`
5. `git commit -m "feat(mobile): ..."`
6. `git push origin <branch>`
7. `git tag vX.Y.Z && git push origin vX.Y.Z`
8. CI builds APK and creates GitHub Release automatically

## Memory files
Persistent memory at `C:\Users\sayr\.claude\projects\C--T1-GIT-ble-tag-jdy23-dynamic\memory\`:
- `project_firmware_flashing.md` — firmware toolchain state
- `project_tag_invisible_bugs.md` — three confirmed firmware bugs + fixes
- `reference_build_flash.md` — pyocd commands
- `reference_hardware_wiring.md` — SWD wiring
- `user_developer.md` — developer context
- `feedback_commit_authorship.md` — no Co-Authored-By
