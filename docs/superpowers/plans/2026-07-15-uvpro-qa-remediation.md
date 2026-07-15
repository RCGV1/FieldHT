# UV-PRO QA Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the QA-reported UV-PRO controls and terminology without emitting unsupported BLE settings writes.

**Architecture:** Keep protocol conversion and display semantics in small pure Swift helpers that can be tested independently. Views render only capability-backed controls; `SettingsViewModel` owns serialized full-settings writes while radio, APRS, and accessory views stage user changes before committing them.

**Tech Stack:** Swift 5, SwiftUI, XCTest, CoreBluetooth, Xcode 26 project.

## Global Constraints

- iOS deployment target is 26.0.
- No third-party dependency may be added.
- Never expose a value that cannot round-trip through the documented current protocol.
- Preserve all unknown packed setting bits when saving a changed setting.
- Use one full BLE write per committed setting change, never per slider tick.
- iGate, Smart Beacon interval, and VGC-specific momentary PTT remain capability-gated until a UV-PRO command capture verifies their messages.

---

### Task 1: Add Test Infrastructure and Pure Radio Presentation Rules

**Files:**
- Modify: `FieldHT.xcodeproj/project.pbxproj`
- Create: `FieldHT/Support/RadioPresentation.swift`
- Create: `FieldHTTests/RadioPresentationTests.swift`

**Interfaces:**
- Produces: `RadioPresentation.sMeterLabel(forPercent:) -> String`
- Produces: `RadioPresentation.screenTimeoutOptions: [RadioChoice]`
- Produces: `RadioPresentation.txLimitOptions: [RadioChoice]`

- [ ] **Step 1: Add an XCTest target and a failing test**

```swift
func testSMeterUsesRadioSignalBands() {
    XCTAssertEqual(RadioPresentation.sMeterLabel(forPercent: 0), "S0")
    XCTAssertEqual(RadioPresentation.sMeterLabel(forPercent: 50), "S5")
    XCTAssertEqual(RadioPresentation.sMeterLabel(forPercent: 100), "S9+")
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project FieldHT.xcodeproj -scheme FieldHT -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:FieldHTTests/RadioPresentationTests/testSMeterUsesRadioSignalBands`

Expected: compilation failure because `RadioPresentation` does not exist.

- [ ] **Step 3: Implement the smallest conversion helper**

```swift
enum RadioPresentation {
    static func sMeterLabel(forPercent value: Int) -> String {
        switch min(max(value, 0), 100) {
        case 0...10: return "S0"
        case 11...20: return "S1"
        case 21...30: return "S2"
        case 31...40: return "S3"
        case 41...50: return "S5"
        case 51...60: return "S6"
        case 61...70: return "S7"
        case 71...80: return "S8"
        case 81...95: return "S9"
        default: return "S9+"
        }
    }
}
```

- [ ] **Step 4: Add failing round-trip option tests and implement valid choices**

```swift
func testScreenTimeoutNeverAdvertisesUnencodableValue() {
    XCTAssertFalse(RadioPresentation.screenTimeoutOptions.contains { $0.value > 31 })
}
```

The implementation must omit the invalid `300s` option and label raw values conservatively until the extended encoding is captured.

- [ ] **Step 5: Run the focused tests and commit**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project FieldHT.xcodeproj -scheme FieldHT -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:FieldHTTests/RadioPresentationTests`

Commit: `test: cover UV-PRO control presentation`

### Task 2: Serialize Settings Writes and Replace TX Sliders

**Files:**
- Modify: `FieldHT/ViewModels/SettingsViewModel.swift`
- Modify: `FieldHT/Views/SettingsView.swift`
- Modify: `FieldHTTests/RadioPresentationTests.swift`

**Interfaces:**
- Consumes: `RadioPresentation.txHoldOptions`, `RadioPresentation.txLimitOptions`
- Produces: `SettingsViewModel.commitSettings(_:)`

- [ ] **Step 1: Write failing tests for choice validity**

```swift
func testTxLimitChoicesFitTheFiveBitProtocolField() {
    XCTAssertTrue(RadioPresentation.txLimitOptions.allSatisfy { (0...31).contains($0.value) })
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project FieldHT.xcodeproj -scheme FieldHT -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:FieldHTTests/RadioPresentationTests/testTxLimitChoicesFitTheFiveBitProtocolField`

- [ ] **Step 3: Add a serialized commit path**

Keep the latest requested `Settings` value, await the active `setSettings` call, then send only the latest different value. Do not cancel an active radio request. On failure, publish the error and refresh settings from the controller.

- [ ] **Step 4: Replace `TX Hold` and `TX Limit` sliders with menu pickers**

Use `Picker` values backed by the pure option arrays. Each selection invokes one `updateTxHoldTime` or `updateTxTimeLimit` call. Update the labels to `Transmission Hold` and `Time-Out Timer` with short footers matching the BTECH manual.

- [ ] **Step 5: Run focused tests, build, and commit**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project FieldHT.xcodeproj -scheme FieldHT -destination 'generic/platform=iOS Simulator'`

Commit: `fix: serialize radio settings saves`

### Task 3: Repair Radio Control Navigation, Signal Meter, and Battery Status

**Files:**
- Modify: `FieldHT/Views/RadioControlView.swift`
- Modify: `FieldHT/Views/Helpers/RssiLinearGauge.swift`
- Modify: `FieldHT/Views/GlobalStatusToolbar.swift`
- Modify: `FieldHT/Views/ChannelSelectionView.swift`
- Modify: `FieldHTTests/RadioPresentationTests.swift`

**Interfaces:**
- Consumes: `RadioPresentation.sMeterLabel(forPercent:)`
- Produces: direct active-group channel selection through `RadioManager.setChannelA(_:)` and `RadioManager.setChannelB(_:)`

- [ ] **Step 1: Write failing S-meter clamping tests**

```swift
func testSMeterClampsOutOfRangeInputs() {
    XCTAssertEqual(RadioPresentation.sMeterLabel(forPercent: -1), "S0")
    XCTAssertEqual(RadioPresentation.sMeterLabel(forPercent: 200), "S9+")
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run the Task 1 test command with `testSMeterClampsOutOfRangeInputs`.

- [ ] **Step 3: Implement radio control changes**

Add an active-channel menu listing the loaded channels in the selected group. Rename the large arrows to `Previous Channel` and `Next Channel`, add accessibility labels, and render `S0` through `S9+` instead of `RSSI` percentage. Keep A/B selection visible only in dual watch; single watch uses the active channel picker.

- [ ] **Step 4: Implement unknown battery display**

When percentage is outside `1...100` or voltage is non-positive, render `Battery unavailable` and omit the red empty battery/zero-voltage combination.

- [ ] **Step 5: Run focused tests, build, and commit**

Run the Task 1 tests and the Task 2 build command.

Commit: `fix: clarify channel controls and radio status`

### Task 4: Reorganize General Settings and Correct Verified Terminology

**Files:**
- Modify: `FieldHT/Views/SettingsView.swift`
- Modify: `FieldHT/Models/PF.swift`
- Modify: `FieldHT/Views/PFSettingsView.swift`
- Modify: `FieldHTTests/RadioPresentationTests.swift`

**Interfaces:**
- Produces: verified labels for Tone, Headset Mode, Keep Headset Connected, Digital Mute, Signaling Preamble, Previous Group, and Next Group.

- [ ] **Step 1: Write failing label tests**

```swift
func testPreviousRegionUsesChannelGroupTerminology() {
    XCTAssertEqual(PFEffectType.prevRegion.displayName, "Previous Group")
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run the Task 1 test command with `testPreviousRegionUsesChannelGroupTerminology`.

- [ ] **Step 3: Implement the terminology and hierarchy update**

Replace the configuration section with clearly ordered routes for General Radio Settings, APRS and Signaling, Channels and Groups, Scan, Programmable Buttons, and Speaker Mic and Bluetooth Audio. Remove `Adaptive Response` from editable General settings until its Smart Beacon mapping is captured. Rename `Toggle Standby` to `Toggle Talk Around`, `Previous Region`/`Next Region` to group terminology, `Disable Tone` to `Key and Operation Tones`, and `Keep AGHFP Link` to `Keep Headset Connected`.

- [ ] **Step 4: Run focused tests, build, and commit**

Run the Task 1 tests and the Task 2 build command.

Commit: `fix: align UV-PRO setting terminology`

### Task 5: Complete the Decoded APRS, Digipeater, and Scan Surfaces

**Files:**
- Modify: `FieldHT/Views/BeaconSettingsView.swift`
- Create: `FieldHT/Views/ScanSettingsView.swift`
- Modify: `FieldHT/Views/SettingsView.swift`
- Modify: `FieldHTTests/RadioPresentationTests.swift`

**Interfaces:**
- Consumes: `BeaconSettings` fields already decoded by `ProtocolDecoder.decodeBeaconSettings(_:)`
- Produces: explicit APRS/BSS, location-sharing, PTT-release, and digipeater sections plus a scan entry.

- [ ] **Step 1: Write failing protocol round-trip tests**

```swift
func testBeaconSettingsRoundTripPreservesDigipeaterValues() throws {
    var settings = BeaconSettings.empty()
    settings.timeToLive = 2
    settings.maxFwdTimes = 2
    let decoded = try ProtocolDecoder.decodeBeaconSettings(ProtocolEncoder.encodeBeaconSettings(settings))
    XCTAssertEqual(decoded.timeToLive, 2)
    XCTAssertEqual(decoded.maxFwdTimes, 2)
}
```

- [ ] **Step 2: Run the focused test to verify it fails or exposes missing test-target linkage**

Run the Task 1 test command with `testBeaconSettingsRoundTripPreservesDigipeaterValues`.

- [ ] **Step 3: Implement grouped APRS and scan screens**

Split the existing beacon form into APRS identity, location sharing, PTT release, and Digipeater sections. Explain that TTL and maximum forwarding must both be nonzero to enable digipeating. Add a Scan screen that uses `RadioManager.setScanning(_:)` and describes scan-eligible channels. Do not add iGate, APRS path, Mic-E, or Smart Beacon interval editors until their protocol messages exist and pass a live round trip.

- [ ] **Step 4: Run focused tests, build, and commit**

Run the Task 1 tests and the Task 2 build command.

Commit: `feat: organize APRS and scan controls`

### Task 6: Make Speaker-Mic Controls Model-Aware and Unambiguous

**Files:**
- Modify: `FieldHT/Views/SpeakerMicView.swift`
- Modify: `FieldHT/Views/SpeakerMicPFSettingsView.swift`
- Modify: `FieldHTTests/RadioPresentationTests.swift`

**Interfaces:**
- Produces: generic accessory copy, BS-22-specific button setup only for a detected BS-22, `Up` and `Down` button labels, and `Press Down` trigger wording.

- [ ] **Step 1: Write failing copy tests**

```swift
func testSpeakerMicLabelIsGenericForUnknownModel() {
    XCTAssertEqual(RadioPresentation.speakerMicName(model: nil, isBS22: false), "Speaker Mic")
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run the Task 1 test command with `testSpeakerMicLabelIsGenericForUnknownModel`.

- [ ] **Step 3: Implement model-aware copy**

Replace unconditional BS22 labels with a detected-model label. Keep the direct programmable-button editor available only to the known BS-22 path. Rename Button 3 and Button 4 to `Up` and `Down`, rename `Edge Trigger` to `Press Down`, and provide a short explanation that long press is not momentary PTT. Show raw gain levels as `Level n` until a live VGC/UV-PRO capture proves a dB mapping.

- [ ] **Step 4: Run focused tests, build, and commit**

Run the Task 1 tests and the Task 2 build command.

Commit: `fix: clarify speaker mic controls`

### Task 7: Live UV-PRO Capability Capture and Full Verification

**Files:**
- Modify: `Scripts/uvpro_ble_region_test.py`
- Create: `.ble-captures/qa-remediation-YYYYMMDD.md` (ignored local evidence)
- Modify: `FieldHT/Protocol/*` only for command mappings verified by capture

**Interfaces:**
- Produces: capture-backed read/write mappings for iGate, Smart Beacon intervals, momentary PTT, VGC/BHM-79 audio prompts, and gain values.

- [ ] **Step 1: Capture baseline read payloads and current UI values from the real UV-PRO**

Run: `python3 Scripts/uvpro_ble_region_test.py --scan --list`

- [ ] **Step 2: Change one setting at a time in the official app and record the matching FieldHT command payload/read-back**

Record baseline and changed values for Smart Beacon min/max interval, iGate routing, speaker-mic audio mode, microphone gain, momentary PTT, and operation tones.

- [ ] **Step 3: Add only verified protocol models, failing tests, and UI controls**

Each new field requires encoder/decoder round-trip coverage and a live read-back before inclusion.

- [ ] **Step 4: Run end-to-end verification and commit each mapped capability separately**

Run the FieldHT build, all XCTest cases, and a live read/write/read-back command sequence for each newly mapped capability.

## Plan Review

- Spec coverage: Tasks 1-6 cover the immediate QA defects that have a current FieldHT protocol model. Task 7 covers the source-confirmed but currently unmapped iGate, Smart Beacon, VGC/BHM-79, momentary PTT, and detailed gain controls.
- Placeholder scan: no implementation task asks for an unidentified setting write; the only intentionally deferred controls are behind the explicit live-capture gate.
- Type consistency: `RadioPresentation` owns pure UI presentation values; `SettingsViewModel` owns full-settings writes; existing `BeaconSettings` remains the APRS data transport.
