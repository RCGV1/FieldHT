# FieldHT

A native iOS app for controlling Benshi UV-PRO handheld radios over Bluetooth Low Energy.

Built entirely in SwiftUI, FieldHT gives you full radio control from your iPhone — channels, zones, VFO tuning, APRS beaconing, satellite tracking, and Siri Shortcuts — without touching the radio's physical controls.

---

## Features

### Radio Control
- **Zone switching** — instantly switch between memory groups (zones) on the radio
- **Channel management** — browse, edit, reorder, and import/export channels per zone as CSV
- **VFO mode** — free-tune channel A or B to any frequency, with TX/RX split and CTCSS/DCS tone support
- **Dual watch** — monitor channel A and B simultaneously with configurable active channel
- **Squelch, scan, PTT lock, tail eliminator** — all common settings in one place
- **Audio** — mic gain, BT mic gain, speaker routing, HM speaker
- **Power** — auto power on/off, power saving mode, screen timeout
- **Programmable buttons** — configure all 6 PF button actions

### APRS / Packet Beaconing
- Configure beacon interval, callsign, symbol, and message
- Auto-share position to a selected channel
- Full APRS symbol picker

### Satellite Tracking
- Real-time pass predictions via SatNOGS / N2YO
- Automatic Doppler-compensated RX/TX frequency updates during a pass
- Satellite mode sends live orbital data (range, azimuth, elevation, altitude) to the radio
- Live Activity on the lock screen showing current pass progress

### Siri Shortcuts & App Intents
All major radio operations are exposed as App Intents for Siri and the Shortcuts app:

| Intent | Example phrase |
|---|---|
| Switch Zone | "Switch FieldHT zone to North Bay" |
| Switch Channel | "Tune FieldHT to Repeater 1" |
| Enter VFO Mode | "Enter FieldHT VFO mode" |
| Set Squelch | "Set FieldHT squelch to 3" |
| Toggle Scan | "Toggle FieldHT scan" |
| Set Dual Watch | "Enable FieldHT dual watch" |
| Set Power Saving | "Enable FieldHT power saving" |
| Set Volume | "Set FieldHT volume to 75" |

All intents return a descriptive error if no radio is connected.

### Quality of Life
- Auto-reconnect to the last paired radio on launch
- Low battery notification when the radio drops below 10 %
- RepeaterBook integration for importing repeater data
- Imperial / metric units toggle

---

## Requirements

| | |
|---|---|
| iOS | 16.0 + |
| Xcode | 15.0 + |
| Radio | Benshi UV-PRO (or compatible) |
| BLE | Required for all radio control features |
| Location | Required for satellite pass predictions |

---

## Building

### 1. Clone the repo

```bash
git clone https://github.com/RCGV1/FieldHT.git
cd FieldHT
```

### 2. Create the secrets config

The N2YO satellite API key is kept out of source control. Copy the template and fill in your key:

```bash
cp Configs/FieldHT-Secrets.xcconfig.template Configs/FieldHT-Secrets.xcconfig
```

Then edit `Configs/FieldHT-Secrets.xcconfig` and set:

```
N2YO_API_KEY = your_key_here
```

Get a free key at [n2yo.com/api](https://www.n2yo.com/api/). Satellite tracking will be degraded without it, but all radio control features work fine.

### 3. Open and run

Open `FieldHT.xcodeproj` in Xcode, select your target device, and run. No additional package fetching is needed — Swift Package Manager resolves dependencies automatically.

---

## Architecture

```
FieldHT/
├── BLE/                  CoreBluetooth layer (scanner, connection lifecycle)
├── Command/              Binary command/reply protocol over BLE
├── Protocol/             Protocol constants, encoder/decoder, bitfield utilities
├── Models/               Value types: Channel, Settings, Status, RadioState, …
├── RadioController.swift High-level radio API (connect, hydrate, set*)
├── ViewModels/           RadioManager (state + actions), SettingsViewModel, ChannelViewModel
├── Views/                All SwiftUI views
├── Intents/              App Intents for Siri / Shortcuts
├── Satellite/            Pass prediction, Doppler, SatNOGS/N2YO client
├── LiveActivity/         Lock screen Live Activity for satellite passes
└── Services/             Notifications, RepeaterBook API, network monitor

Widget/                   WidgetKit extension
FieldHTLiveActivity/      Live Activity extension
```

The BLE transport speaks a binary command/reply protocol to the radio over a single GATT service. `RadioController` wraps that transport and exposes an async/await API. `RadioManager` is the `@MainActor` `ObservableObject` that the UI binds to — it owns connection state, auto-reconnect, and all fire-and-forget radio actions. App Intents reach `RadioManager` through `RadioIntentBridge`, a lightweight singleton the app registers on launch.

---

## Contributing

Issues and pull requests are welcome. Please open an issue first for anything beyond small fixes so we can align on direction.

---

## Support

If FieldHT saves you time at the radio, you can [buy me a coffee](https://buymeacoffee.com/benfaer). It's appreciated but never required.

---

## License

MIT — see [LICENSE](LICENSE) for details.
