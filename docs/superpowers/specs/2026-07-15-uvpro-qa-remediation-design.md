# UV-PRO QA Remediation Design

## Goal

Make FieldHT's radio, settings, APRS, and speaker-mic flows match the
documented UV-PRO behavior while preventing the app from writing values that
the current BLE protocol does not verify.

## Evidence

- The official UV-PRO manual documents channel groups, Talk Around, scanning,
  dual-watch A/B behavior, TX time limits, and screen timeouts up to 300
  seconds: https://baofengtech.com/wp-content/uploads/2024/08/BTECHpackaging_UVPRO_Manual_Rev3.pdf
- The official BTECH app manual documents APRS/BSS, Smart Beaconing, gateway,
  digipeater, audio/PTT, headset, tone, scan, and programmable-key behavior:
  https://baofengtech.com/wp-content/uploads/2025/11/BTECH-APP-Updated-Manual-2025-9-9.pdf
- The official firmware changelog says Smart Beacon maximum interval and
  additional programmable actions arrived in UV-PRO firmware 0.9.2:
  https://baofengtech.com/staging/uv-pro-firmware-changelog/

## Constraints

- `Settings.txHoldTime`, `Settings.txTimeLimit`, and `Settings.screenTimeout`
  are packed protocol values, not automatically seconds. FieldHT must never
  advertise a wall-clock value unless the encoded value is verified.
- FieldHT currently has no decoded command model for iGate configuration,
  Smart Beacon interval bounds, VGC/BHM-79-specific controls, or external
  PTT momentary behavior. Those controls require a real-radio capture and
  read-back verification before being exposed as editable settings.
- All radio setting mutations must be serialized. Continuous UI interaction
  must not produce a sequence of full BLE settings writes.
- Do not hard-code an accessory model. Display BS-22 only when the connected
  accessory identifies as BS-22; otherwise use the detected model or the
  generic `Speaker Mic` label.
- iOS deployment target remains 26.0. No new third-party dependencies.

## Product Decisions

### Settings transport

Replace live write sliders for transmit settings with discrete controls that
stage a raw radio value locally and make one write when the selection changes.
The settings view model will serialize saves and retain the latest intended
settings until the in-flight command completes. A failed write must leave a
visible error and refresh the radio state rather than silently claiming a
value was applied.

Screen timeout must use only values that round-trip through the 5-bit protocol
until the real on-wire representation for longer documented values is captured.
The invalid `300s` menu item must be removed now because it is currently
truncated to `12` before transmission.

### Radio control

Keep dual-watch's actual A/B behavior but label it plainly. In single-watch
mode, show an explicit channel picker for the active memory group and provide
previous/next channel controls with accessibility labels. Replace the raw
`RSSI` percentage label with an S-meter backed by the radio's documented
four-bit signal-strength indication; it must not pretend to be dBm.

### Settings organization

The settings root becomes a navigation-focused surface:

1. General radio settings (audio, transmission, power, display, advanced).
2. APRS and signaling (the existing packet/beacon data plus digipeater
   settings already decoded by FieldHT).
3. Channels and groups.
4. Scan.
5. Programmable buttons.
6. Speaker mic and Bluetooth audio when supported.
7. Device status.

Existing protocol fields get names and explanations that match the official
manual: `Talk Around`, `Tone`, `Headset Mode`, `Keep Headset Connected`,
`Digital Mute`, and `Signaling Preamble`. The unverified generic
`Adaptive Response` control is removed from General settings rather than
misrepresented as Smart Beaconing.

### APRS, signaling, and scan

The existing beacon packet model supports APRS/BSS format, callsign, SSID,
symbol, message, location sharing, PTT release flags, power-voltage flag,
allow-position-check, TTL, and maximum forwarding count. Present those under
meaningful APRS, signaling, and digipeater sections, with one Save operation.
Add a Scan entry that drives the already-supported memory-channel scan and
explains that channel scan uses per-channel scan eligibility.

Do not create iGate or Smart Beacon interval editors until their commands are
decoded and verified on the UV-PRO. Record them as capability-gated work in
the UI instead of exposing inert or unsafe switches.

### Speaker mic and buttons

Make accessory copy model-aware and change numeric gain display to a labeled
radio gain level only until a dB conversion is captured from the radio. Rename
the two known side controls to `Up` and `Down`, replace `Edge Trigger` with
`Press Down`, and rename `Previous Region` to `Previous Group`.

Document press behavior in the UI and show momentary/external-PTT capabilities
only when the connected accessory reports a supported action. Do not synthesize
a momentary setting from a long press.

### Connection and status stability

Avoid invalid battery indicators: unknown battery data must display as
unavailable instead of `0% (0.0V)`. Connection scanning and settings refreshes
must retain stable list identity and must not be retriggered by each radio
state publication.

## Acceptance Criteria

- Changing TX Hold or TX Limit produces at most one complete settings write per
  committed selection, never a write per drag tick.
- FieldHT does not encode `300` into the current five-bit screen-timeout
  field, and every exposed setting value round-trips through its encoder and
  decoder.
- A single-watch user can select any channel in the active group directly;
  A/B selection is only presented when dual watch is enabled.
- Signal strength is displayed as an S-meter rather than a raw `RSSI` percent.
- No visible speaker-mic copy calls every accessory `BS22`.
- APRS/BSS, digipeater, and scan controls are grouped and labeled according to
  the official documentation and existing decoded command model.
- iGate, Smart Beacon intervals, and model-specific momentary PTT controls
  remain unavailable until their read/write mappings pass a live UV-PRO
  round-trip test.
- Unit tests cover value conversion, save serialization, and model-aware copy;
  the FieldHT scheme builds with Xcode.
