# Battery Harbor

[简体中文](README.md) | [English](README.en.md)

Battery Harbor is a clean-room, native macOS menu bar utility for battery care. It provides a configurable charge limit, charging pause, temporary full charge, power monitoring, per-app energy ranking, and scheduled actions.

> Version `0.1.0-alpha.2` is a community technical preview. Its low-level charging controller writes to AppleSMC. Hardware control is intended only for users who understand and complete the built-in safety self-test on a test machine. Compatibility across Mac models and macOS releases is still being verified.

## Project status

| Area | Status | Notes |
| --- | --- | --- |
| Battery and power monitoring | Complete | Charge, temperature, health, cycle count, voltage, current, and live power |
| Menu bar and dashboard | Complete | Simplified Chinese/English, native icons, consistent glass styling, and horizontal tab transitions |
| App energy ranking | Complete | Groups helper processes under their host app; live, 1-hour, and 24-hour views |
| Charge policy | Complete | Charge limit, pause, temporary full charge, 3% hysteresis, and optional discharge above the limit |
| Root Helper | Tested on one Apple Silicon Mac | XPC v3 handshake, signature checks, allowlist, read-back verification, rollback, and restoration self-test |
| Schedules and Shortcuts | Complete | Weekday/time schedules, execution log, and four App Intents |
| Automatic protection | Complete | High-temperature pause, sleep pause, wake recovery, and background enforcement |
| Automated tests | 32 unit tests passing | CI builds and tests without installing the Helper or writing to SMC |
| Public release | Local `0.1.0-alpha.2` candidate built | MIT licensed; the current community DMG passed static signature verification, and the previous candidate passed clean-account testing with no Apple ID or maintainer certificate; no Developer ID notarized build is planned yet |

## Features

- Drag to set a charge limit and pause automatically at the limit
- Pause/resume charging, temporarily charge to 100%, and optionally discharge above the limit
- Live power split between adapter input, system load, and battery flow
- Charge/discharge history sampled every two seconds
- Live and local 24-hour per-app energy ranking
- Battery health, temperature, cycle count, capacity, voltage, and current details
- Weekday/time schedules for limits, pause, resume, and temporary full charge
- Shortcuts actions for status, charge limit, pause/resume, and temporary full charge
- Four-stage calibration, high-temperature protection, and sleep protection
- CSV export and a diagnostic report that excludes serial numbers and Apple IDs

## Safety model

The regular app process does not write to SMC directly. Every control command must pass through the signed root Helper and satisfy all of these checks:

1. Client Bundle ID and code-signature verification. Apple-signed builds require the App and Helper to share a Team; self-signed community builds require an exact leaf-certificate match. Identity-less ad-hoc builds are rejected.
2. Root execution and XPC protocol v3 handshake.
3. Fixed SMC key allowlist and hardware capability checks.
4. A startup self-test that temporarily changes `CHTE`, reads it back, restores the original value, and verifies the restored value.
5. Read-back verification after every production write, with reverse-order rollback on failure.

The Helper locks hardware control again after the Helper or Mac restarts. See [Hardware control safety verification](Docs/HardwareVerification.md) before testing real charge control.

## Requirements

- macOS 13 or later
- Apple Silicon Mac for the current hardware-write implementation
- Full Xcode for local development
- App and Helper signed by the same Personal/Developer Team or by the same local self-signed code-signing certificate

Intel Macs, additional Apple Silicon generations, and more macOS versions still need a broader compatibility matrix.

## Build locally

### Xcode (recommended)

Open `BatteryHarbor.xcodeproj`. In **Signing & Capabilities**, select the same Team for `BatteryHarbor` and `BatteryHarborHelper`, then run the `BatteryHarbor` scheme.

Unsigned command-line build:

```sh
xcodebuild \
  -project BatteryHarbor.xcodeproj \
  -scheme BatteryHarbor \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/XcodeDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

An unsigned build verifies compilation only. It cannot install or connect to the root Helper.

### Swift Package

```sh
swift run BatteryHarbor
```

`swift run` is useful for UI and read-only monitoring. It does not create the complete app bundle with the LaunchDaemon and therefore cannot validate real charging control.

## Testing

See the bilingual [testing guide](Docs/Testing.md).

Run Swift Package tests:

```sh
swift test
```

Run Xcode tests:

```sh
xcodebuild \
  -project BatteryHarbor.xcodeproj \
  -scheme BatteryHarbor \
  -destination 'platform=macOS' \
  -derivedDataPath .build/XcodeDerivedData \
  test
```

Automated tests never install the Helper or write to SMC. Real hardware control must be verified manually on the tester's own Mac.

## Data and privacy

The current source contains no network requests, telemetry, ads, or third-party analytics. Preferences, schedules, and the latest 24 hours of power/app energy samples remain on the Mac. CSV files and diagnostic reports are created only when the user explicitly exports them. See [PRIVACY.md](PRIVACY.md).

## Documentation

- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Privacy](PRIVACY.md)
- [Changelog](CHANGELOG.md)
- [Unnotarized community DMG: install, upgrade, and uninstall](Docs/CommunityDMG.en.md)
- [Compatibility matrix](Docs/Compatibility.md)
- [Clean-account release verification](Docs/CleanEnvironmentTest.md)
- [Hardware control safety verification](Docs/HardwareVerification.md)

## Maintainer

[MUU3327](https://github.com/MUU3327)

## License

Battery Harbor is released under the [MIT License](LICENSE). Copyright © 2026 MUU3327.
