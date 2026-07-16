# BTECH UV Programmer 2.9.2.1: Protocol and Behavior Evidence

## Scope and provenance

This is a read-only interoperability note based on the locally available public
Android distribution:

- Artifact: `/Users/benjaminfaershtein/Downloads/BTECH+UV+Programmer_2.9.2.1_apkcombo.com.xapk`
- Base package inside the XAPK: `com.benshikj.ht.btech.ham.apk`
- Declared package: `com.benshikj.ht.btech.ham`
- Declared version: `2.9.2.1` (`versionCode` `2090201`)
- Decompiled source root: `/tmp/btech-jadx`

The XAPK metadata reports the package and version directly, and the decoded base
APK manifest independently agrees. See the XAPK `manifest.json` and
`/tmp/btech-jadx/resources/AndroidManifest.xml:1-14`.

This document describes what the stock app source demonstrates. It does **not**
claim the observed behavior applies to every firmware revision, radio model, or
transport. It does not include credentials, private data, or copied third-party
source.

### Limits

- JADX output is reconstructed Java/Kotlin and contains obfuscated names. Treat
  names such as `y4.a` as source locations, not stable vendor API names.
- This analysis does not include a packet capture from a physical radio. Exact
  timing, device-side error handling, and which capability revisions exist on a
  particular radio still require a hardware trace.
- The app supports several transports and product families. The BLE facts below
  apply to its GAIA-style BLE link; the wider command enum contains functionality
  not necessarily available on a UV-PRO.

## Architecture inferred from the artifact

The app separates user interfaces, a model-aware link layer, transport adapters,
and packed command payloads:

| Layer | Evidence | Implementation meaning |
| --- | --- | --- |
| Android application and UI | The manifest launches `com.dw.ht.BTActivity`; its app class is `com.dw.ht.Main` (`AndroidManifest.xml:103-157`). Frequency scan is `s4.g3`; settings and satellite screens are separate fragments/packages. | Keep FieldHT presentation state independent of the radio transport. |
| Link/session orchestration | `v4.l1` owns link state, command submission, connection listeners, status listeners, and capability-aware behavior (`v4/l1.java:657-705`, `:776-805`). `v4.c0` performs the initial settings/channel/range sync (`v4/c0.java:1161-1205`). | Model connection state explicitly; do not infer readiness solely from CoreBluetooth connection. |
| Command catalog | The zero-based `v4.v` enum is the command-number catalog (`v4/v.java:4-82`). | Command numbers in this document are enum ordinals, as passed by `v4.l1.a` at `v4/l1.java:657-668`. |
| BLE adapter | `y1.d` discovers the service, enables notify/indicate, queues writes, and relays packets to the link handler (`y1/d.java:78-174`, `:274-372`). | Match the BLE envelope and serialized writes; keep it separate from SPP/USB framing. |
| Packed payloads | Settings are a bit-packed structure (`v4/a2.java:124-191`, `:296-305`); frequency-mode parameter and status structures are `y4.a` and `y4.b`. | Use a tested bit writer/reader and keep firmware-version gates next to serializers. |

## Transport and framing

### BLE: compact service envelope

The decompiled BLE client uses these UUIDs:

| Purpose | UUID | Evidence |
| --- | --- | --- |
| Service | `00001100-d102-11e1-9b23-00025b00a5a5` | `/tmp/btech-jadx/sources/y1/e.java:11-13` |
| Write characteristic | `00001101-d102-11e1-9b23-00025b00a5a5` | `/tmp/btech-jadx/sources/y1/e.java:14-16` |
| Notify/indicate characteristic | `00001102-d102-11e1-9b23-00025b00a5a5` | `/tmp/btech-jadx/sources/y1/e.java:17-21` |
| Client Characteristic Configuration Descriptor | standard `0x2902` UUID | `/tmp/btech-jadx/sources/y1/e.java:20-21` |

After service discovery, the stock app enables notifications or indications on
the receive characteristic depending on its advertised properties, then stores
the write characteristic as the transmit endpoint
(`/tmp/btech-jadx/sources/y1/d.java:133-154`).

For a BLE write, it constructs a four-byte big-endian command header followed by
the command payload:

```text
byte 0..1  family / namespace (big endian)
byte 2..3  command identifier (big endian)
byte 4..n  payload
```

The header construction is directly shown at
`/tmp/btech-jadx/sources/y1/d.java:274-285`; writes are queued and advanced at a
10 ms delay in `:330-368`. Incoming notifications are parsed with the same
header/payload parser and forwarded into the main link handler
(`:82-98`, `:320-327`).

The high-level radio commands in `v4.v` are sent through family `2`: the link
passes the enum ordinal as the command identifier
(`/tmp/btech-jadx/sources/v4/l1.java:657-668`). The BLE packet presentation
labels family `2` as `BS` and resolves its command through `v4.v`
(`/tmp/btech-jadx/sources/y1/g.java:20-41`).

### SPP/USB: distinct GAIA-style outer frame

The stock app also has a classic Bluetooth/USB transport, represented by `g3.c`.
It is **not** the BLE GATT envelope above. Its outgoing frame builder emits:

```text
FF 01 flags payloadLength commandFamily(2 bytes, big endian)
commandId(2 bytes, big endian) payload [xor checksum when flags bit 0 is set]
```

This layout and the maximum payload length of 254 are evidenced by
`/tmp/btech-jadx/sources/g3/a.java:87-119`. Its reader finds `0xFF`, uses the
flags and length to reassemble frames, and dispatches decoded packets
(`/tmp/btech-jadx/sources/g3/c.java:315-358`). This is useful evidence for
cross-transport tooling, but it must not be written directly to the BLE write
characteristic.

### Responses and errors

The generic packet parser treats the high bit of the command identifier as a
response/error flag and exposes the low 15 bits as the command ID
(`/tmp/btech-jadx/sources/g3/d.java:72-77`, `:100-122`). When the response flag
is present, the first payload byte is decoded as a status enum: `SUCCESS`,
`NOT_SUPPORTED`, `NOT_AUTHENTICATED`, `INSUFFICIENT_RESOURCES`,
`AUTHENTICATING`, `INVALID_PARAMETER`, `INCORRECT_STATE`, or `IN_PROGRESS`
(`/tmp/btech-jadx/sources/g3/a.java:45-68`).

FieldHT should preserve this distinction in its command layer: a transport
write being accepted is not proof that the radio accepted the command.

## Command families

`v4.v` is the verified family-2 radio command catalog. The following grouping
is organizational, not a claim that every command is supported by every device.

| Family | Command enum members evidenced in `v4.v` |
| --- | --- |
| Device/session | `GET_DEV_ID`, registration time/info/status reads, `UNLOCK`, `SET_TIME`, BLE connection parameters |
| Notifications | `REGISTER_NOTIFICATION`, `CANCEL_NOTIFICATION`, `GET_NOTIFICATION`, `EVENT_NOTIFICATION` |
| Core configuration | `READ_SETTINGS`, `WRITE_SETTINGS`, `STORE_SETTINGS`, `READ/WRITE_ADVANCED_SETTINGS`, `READ/WRITE_ADVANCED_SETTINGS2` |
| Channels and regional data | `READ_RF_CH`, `WRITE_RF_CH`, `READ/WRITE_REGION_CH`, `READ/WRITE_REGION_NAME`, `SET_REGION` |
| Radio operation | volume, radio status/mode/seek/frequency, `FREQ_MODE_SET_PAR`, `FREQ_MODE_GET_STATUS`, frequency ranges, TX time limit |
| Signaling/data | `HT_SEND_DATA`, `SET_POSITION`, APRS path read/write, KISS/digital signal, trusted-device and identity commands |
| Programmable/audio features | `GET/SET_PF`, `GET_PF_ACTIONS`, `PLAY_TONE`, `SET_VOC`, `GET_VOC` |
| Satellite | `SET_SATELLITE_INFO` |

The exact catalog and ordinal ordering are at
`/tmp/btech-jadx/sources/v4/v.java:4-82`.

## Frequency-mode protocol: commands 35 and 36

### Command IDs

`FREQ_MODE_SET_PAR` is ordinal **35** and `FREQ_MODE_GET_STATUS` is ordinal
**36** in `v4.v` (`/tmp/btech-jadx/sources/v4/v.java:34-42`). With the family-2
BLE envelope, that is:

```text
0x0002 0x0023  frequency-mode parameter payload  (command 35)
0x0002 0x0024  empty payload                       (command 36 request)
```

This is source-derived, not a captured byte sequence. The stock scan fragment
submits its parameter object through command 35
(`/tmp/btech-jadx/sources/s4/g3.java:910-917`), while its base class requests
command 36 and decodes the payload as `FreqModeStatus`
(`/tmp/btech-jadx/sources/s4/t2.java:42-60`).

### Command 35 parameter payload

`y4.a` serializes a 14-byte payload below firmware revision 137 and a 16-byte
payload at revision 137 or newer (`/tmp/btech-jadx/sources/y4/a.java:53-65`).
Fields are emitted in this bit order:

| Bits | Field | Evidence |
| --- | --- | --- |
| 2 | RX modulation enum ordinal | `y4/a.java:60-62` |
| 30 | RX frequency (raw integer) | `y4/a.java:60-62` |
| 2 | TX modulation enum ordinal | `y4/a.java:60-62` |
| 30 | TX frequency (raw integer) | `y4/a.java:60-62` |
| 16 | RX CTCSS/DCS value | `y4/a.java:60-62` |
| 16 | TX CTCSS/DCS value | `y4/a.java:60-62` |
| 1 | TX-power boolean | `y4/a.java:60-62` |
| 3 | scan step enum ordinal | `y4/a.java:60-62` |
| 4 | mode enum ordinal | `y4/a.java:60-62` |
| 6 | reserved zeros | `y4/a.java:61` |
| 2 | power change selector | `y4/a.java:61`, `y4/d.java:4-8` |
| 16, revision >= 137 | additional value | `y4/a.java:62-64` |

The source does not state the integer unit in the serializer. The scan UI
formats these raw values as MHz by dividing by 1,000,000
(`/tmp/btech-jadx/sources/s4/g3.java:712-728`), which supports interpreting
the raw frequency as Hz.

#### Mode ordinals

The mode field is an enum ordinal. Verified values are:

| Value | Mode |
| --- | --- |
| 0 | `MODE_OFF` |
| 1 | `MODE_UP` |
| 2 | `MODE_DOWN` |
| 3 | `MODE_EXACT` |
| 4 | `MODE_CREATE_TEAM` |
| 5 | `MODE_JOIN_TEAM` |
| 6 | `MODE_NOAA_SCAN` |
| 7 | `MODE_TONE_SCAN` |
| 8 | `ONE_CLICK` |
| 9 | `KISS` |
| 10 | `SATELLITE` |

Source: `/tmp/btech-jadx/sources/y4/c.java:6-33`.

#### Scan step ordinals

| Value | Step |
| --- | --- |
| 0 | 5 kHz |
| 1 | 6.25 kHz |
| 2 | 10 kHz |
| 3 | 12.5 kHz |
| 4 | 15 kHz |
| 5 | 25 kHz |

The ordinal-to-label mapping is in `/tmp/btech-jadx/sources/y4/e.java:6-28`;
the status model converts those values into raw Hz at
`/tmp/btech-jadx/sources/y4/b.java:134-149`.

### Command 36 status payload

`y4.b` starts reading at bit offset 8 and then consumes the following 106 bits
(`/tmp/btech-jadx/sources/y4/b.java:214-240`):

| Bit offset after the first 8 bits | Width | Field |
| --- | ---: | --- |
| 0 | 2 | RX modulation |
| 2 | 30 | RX frequency |
| 32 | 2 | TX modulation |
| 34 | 30 | TX frequency |
| 64 | 16 | RX CTCSS/DCS |
| 80 | 16 | TX CTCSS/DCS |
| 96 | 1 | TX power |
| 97 | 3 | scan step |
| 100 | 4 | mode |
| 104 | 1 | tuned |
| 105 | 1 | seek |

The first byte is intentionally skipped by this status decoder. In the generic
response model, status/error replies use the first payload byte as a result
code, so treating it as a response prefix is a reasonable interoperability
deduction, but it is not explicitly named by `y4.b`. FieldHT should retain the
prefix in raw packet logging until a physical trace confirms it for each
firmware.

The status object exposes the complete field interpretation in its diagnostic
string (`/tmp/btech-jadx/sources/y4/b.java:206-207`). Its `tuned` and `seek`
flags are used by the scan controller, not merely displayed.

## Stock frequency-scan lifecycle

The stock implementation is a device-driven scan, not an app-side loop that
writes a new VFO channel for every step.

1. Entering the frequency scan clears active satellite selection
   (`/tmp/btech-jadx/sources/s4/g3.java:790-794`).
2. It reads the current command-36 status, keeps user-selected start/end,
   modulation, and fine-tuning step in preferences, and obtains device frequency
   ranges during link synchronization (`s4/g3.java:753-809`, `:1133-1145`;
   `v4/c0.java:1161-1182`).
3. A manual fine step sends command 35 with `MODE_EXACT`. Scan-up and scan-down
   send `MODE_UP` / `MODE_DOWN` and pre-adjust the RX frequency by the selected
   scan step (`/tmp/btech-jadx/sources/s4/g3.java:994-1023`).
4. Starting/stopping toggles `MODE_UP` versus `MODE_OFF`
   (`/tmp/btech-jadx/sources/s4/g3.java:1000-1008`). Leaving the screen also
   sends `MODE_OFF` (`:1157-1173`).
5. On each status update, a frequency outside the configured start/end range is
   replaced with the appropriate endpoint for the current direction
   (`/tmp/btech-jadx/sources/s4/g3.java:448-473`, `:1105-1108`).
6. While scanning, a `tuned` status stores/updates the result. When the
   `freq_scan_auto_scan` preference is true, the app submits the next command-35
   parameter to continue. It also auto-continues when no tune occurred and the
   frequency did not change (`/tmp/btech-jadx/sources/s4/g3.java:1109-1128`;
   next-step helper at `:587-596`).

This explains the required FieldHT behavior: scan should issue command 35 in
`UP`, `DOWN`, `EXACT`, and `OFF` modes, honor the radio-reported status,
wrap only inside a user-selected range, and provide an explicit auto-continue
option. Using mode value 10 (`SATELLITE`) for advanced scanning is incompatible
with the stock app's own scan screen.

## Notification and capability gates

The stock app registers `HT_STATUS_CHANGED` and, only when firmware capability
143 is present, `FREQ_SCAN_STATUS_CHANGED`
(`/tmp/btech-jadx/sources/v4/c0.java:775-801`). Capability definitions identify
that feature as `FreqScanStatusChangedNotification(143)` and show other
feature gates such as satellite mode (137), satellite info (141), position
notifications (131), Mic-E configuration (135/136), and smart-beacon maximum
interval (146) (`/tmp/btech-jadx/sources/v4/a0.java:131-168`).

When the frequency-scan status notification is not supported, the base link
polls command 36 on a schedule: 100 ms during seek-up/seek-down, 500 ms for
other active modes, and 5 seconds while off
(`/tmp/btech-jadx/sources/v4/l1.java:319-323`, `:390-424`).

Registration and cancellation are batched only when the batch-registration
capability is present; otherwise the app sends one command per notification
(`/tmp/btech-jadx/sources/v4/l1.java:426-452`).

## Other implementation evidence

### Settings, channels, and VFOs

- The initial sync reads settings, all RF channels, BSS settings, frequency
  ranges, and APRS path in sequence (`/tmp/btech-jadx/sources/v4/c0.java:1161-1205`).
- The stock app explicitly schedules channel indices **252** and **251** for
  read when firmware revision is at least 97
  (`/tmp/btech-jadx/sources/v4/c0.java:795-801`).
- The packed settings model gives special meaning to 252 and 251: 252 selects
  A, 251 selects B, with the active side represented by its `doubleChannel`
  enum (`/tmp/btech-jadx/sources/v4/a2.java:202-204`, `:247-275`). This is
  strong evidence that these are the app's two VFO slots.
- Channel writes are queued per channel and followed by `STORE_SETTINGS`
  (`/tmp/btech-jadx/sources/v4/c0.java:2355-2428`).

### Speaker mic and audio

The radio settings bit field contains local speaker, mic gain, Bluetooth mic
gain, AGHFP call mode, audio relay, AGHFP link retention, speaker mode, digital
mute, VOX/noise suppression, and alarm volume fields
(`/tmp/btech-jadx/sources/v4/a2.java:124-183`, `:308-310`). The device-settings
screen has controls for AGHFP mode, Bluetooth mic gain, device speaker, and mic
gain (`/tmp/btech-jadx/sources/k5/s.java:441-493`).

Separately, the speaker-mic BLE audio transport has a command set including
`SET_BLE_AUDIO`, tone playback, and Opus audio payloads
(`/tmp/btech-jadx/sources/y1/h.java:6-59`). The app sends `SET_BLE_AUDIO` on
its audio-link startup path (`/tmp/btech-jadx/sources/y1/a.java:558-565`).
The artifact demonstrates that these features exist; it does not establish
FieldHT-safe values or an end-to-end iOS audio-routing contract.

### APRS and signaling

The command catalog has `SET_POSITION`, `SET_APRS_PATH`, `GET_APRS_PATH`, and
`GET_POSITION` (`/tmp/btech-jadx/sources/v4/v.java:36-37`, `:76-81`). The link
uses a firmware-revision-dependent position serializer and sends it through
`SET_POSITION` (`/tmp/btech-jadx/sources/v4/l1.java:965-980`). APRS path is
read during link sync only at capability/revision 86 or later
(`/tmp/btech-jadx/sources/v4/c0.java:1176-1182`).

The source also explicitly gates position-change notifications, Mic-E,
send-ID-by-APRS, and smart-beacon intervals by capability revision
(`/tmp/btech-jadx/sources/v4/a0.java:131-168`). This supports modeling them as
separate, gated settings rather than exposing toggles that cannot be read back.

### Satellite mode

Satellite tracking is a distinct flow. It computes/configures satellite
parameters, uses `MODE_EXACT` by default, upgrades to `SATELLITE` only when the
radio reports SatelliteMode capability, and can send a separate
`SET_SATELLITE_INFO` command when supported
(`/tmp/btech-jadx/sources/com/dw/ht/satellite/b.java:752-820`). Frequency scan
first disconnects this flow, as noted above. These paths should remain separate
in FieldHT.

## Verified versus inferred

| Item | Classification | Basis |
| --- | --- | --- |
| Artifact package/version and split layout | Verified | XAPK `manifest.json`; decoded manifest `AndroidManifest.xml:1-14` |
| BLE service and characteristic UUIDs | Verified | `y1/e.java:11-21` |
| BLE four-byte family/command big-endian envelope | Verified | `y1/d.java:274-285` |
| Family-2 command numbers are `v4.v` ordinals | Verified | `v4/l1.java:657-668`, `v4/v.java:4-82` |
| Command 35/36 identities | Verified | `v4/v.java:34-42` |
| Command-35 parameter bit layout and version size gate | Verified | `y4/a.java:53-65` |
| Command-36 status field layout after its first byte | Verified | `y4/b.java:214-240` |
| First status byte is generic response status prefix | Inferred | `y4.b` skips it; generic response decoder uses first payload byte at `g3/d.java:100-105` |
| Raw frequency unit is Hz | Inferred with strong UI evidence | UI renders raw value / 1,000,000 at `s4/g3.java:712-728` |
| 251/252 are VFO B/A respectively | Inferred with strong settings evidence | sync requests both and special settings selection logic at `v4/c0.java:795-801`, `v4/a2.java:247-275` |
| Exact on-air scanning dwell/timing | Not established | Requires physical packet trace and radio test |
| Any feature works on a given FieldHT-connected radio | Not established | Capability and firmware revision must be read from that radio |

## Prioritized FieldHT backlog

1. **Replace the current advanced-scan behavior with command-35 frequency
   modes.** Add a small typed protocol model for `OFF`, `UP`, `DOWN`, and
   `EXACT`; make satellite mode unavailable to scan controls. Verify every
   transition against command-36 status.
2. **Implement a command-36 status decoder and error-aware command pipeline.**
   Preserve raw frames, decode the response flag/status, and surface
   `NOT_SUPPORTED`, `INVALID_PARAMETER`, and `INCORRECT_STATE` distinctly.
3. **Add capability- and revision-gated scan updates.** Register the frequency
   scan notification when capability 143 is available; otherwise poll at the
   stock timings. Do not claim live scanning before either path is verified
   against a radio.
4. **Add range-aware scan state.** Read frequency ranges before enabling scan,
   validate start/end/modulation, wrap in the selected direction, and offer
   auto-continue only after a tune/no-progress status as the stock logic does.
5. **Formalize VFO A/B support.** Treat 252 and 251 as special slots only after
   device revision/capability confirmation; keep memory channels separate from
   the active VFO state and persist selection intentionally.
6. **Split supported settings from unexplained fields.** Build settings screens
   from read/write-backed fields with explicit units (notably gain and time
   limits), and retain unknown bit fields without exposing them as toggles.
7. **Keep satellite and scanning as independent controllers.** Entering scan
   should terminate satellite frequency mode; entering satellite tracking should
   use its capability gate and dedicated satellite-info flow.
8. **Add hardware evidence tests.** Capture BLE request/response pairs on a
   UV-PRO for mode 35, command 36, start/stop, wrap, tune, auto-continue,
   notification registration, and reconnect. Convert each confirmed packet into
   a fixture-backed FieldHT protocol test.

