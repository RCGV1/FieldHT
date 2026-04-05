#!/usr/bin/env python3
import json
import os
import subprocess
import sys
from collections import Counter
from pathlib import Path


BUNDLE_ID = os.environ.get("FIELDHT_BUNDLE_ID", "BenFaer.FieldHT")
REMOTE_FILES = [
    ("current", "Library/Caches/fieldht_ble_capture.jsonl"),
    ("previous", "Library/Caches/fieldht_ble_capture.jsonl.1"),
]


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def detect_connected_device_id() -> str | None:
    override = os.environ.get("FIELDHT_DEVICE_ID")
    if override:
        return override

    json_path = Path("/tmp/fieldht-devices.json")
    result = run(
        [
            "xcrun",
            "devicectl",
            "list",
            "devices",
            "--json-output",
            str(json_path),
        ]
    )
    if result.returncode != 0 or not json_path.exists():
        return None

    try:
        payload = json.loads(json_path.read_text())
    except json.JSONDecodeError:
        return None

    devices = payload.get("result", {}).get("devices", [])
    connected_phones = []
    for device in devices:
        state = device.get("deviceProperties", {}).get("bootState") or device.get("state")
        identifier = device.get("identifier")
        platform = device.get("hardwareProperties", {}).get("platform")
        model = device.get("hardwareProperties", {}).get("deviceType")
        name = device.get("deviceProperties", {}).get("name", "")
        connection_state = device.get("connectionProperties", {}).get("tunnelState")
        if (
            identifier
            and platform == "iOS"
            and model == "iPhone"
            and (device.get("visibilityClass") == "default")
        ):
            connected_phones.append(
                (
                    device.get("identifier"),
                    name,
                    device.get("connectionProperties", {}).get("pairingState"),
                    connection_state,
                )
            )

    for identifier, _name, pairing_state, connection_state in connected_phones:
        if pairing_state == "paired" and connection_state == "connected":
            return identifier

    if connected_phones:
        return connected_phones[0][0]
    return None


def copy_from_device(device_id: str, remote_path: str, destination: Path) -> bool:
    destination.parent.mkdir(parents=True, exist_ok=True)
    result = run(
        [
            "xcrun",
            "devicectl",
            "device",
            "copy",
            "from",
            "--device",
            device_id,
            "--domain-type",
            "appDataContainer",
            "--domain-identifier",
            BUNDLE_ID,
            "--source",
            remote_path,
            "--destination",
            str(destination),
        ]
    )
    return result.returncode == 0


def load_entries(path: Path):
    entries = []
    if not path.exists():
        return entries
    for line in path.read_text(errors="ignore").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            entries.append({"entry": "invalid_json", "raw": line})
    return entries


def recent_entries(entries, limit: int = 12):
    with_times = [entry for entry in entries if entry.get("unix_ms")]
    with_times.sort(key=lambda entry: entry.get("unix_ms", 0))
    return with_times[-limit:]


def summarize(entries):
    packet_count = 0
    note_count = 0
    by_category = Counter()
    unknown_packets = Counter()
    raw_events = Counter()
    decode_errors = Counter()
    packet_uuids = Counter()
    protocol_labels = Counter()

    for entry in entries:
        kind = entry.get("entry")
        if kind == "packet":
            packet_count += 1
            packet_uuids[entry.get("uuid", "")] += 1
        elif kind == "note":
            note_count += 1
            category = entry.get("category", "")
            by_category[category] += 1
            fields = entry.get("fields", {}) or {}
            if category == "protocol_message":
                protocol_labels[(fields.get("label", ""), fields.get("reply", ""))] += 1
            if category == "unknown_packet":
                unknown_packets[(entry.get("message", ""), fields.get("label", ""))] += 1
            elif category in {"raw_event", "unknown_event"}:
                raw_events[(fields.get("name", ""), fields.get("type", ""), fields.get("body", "")[:24])] += 1
            elif category == "decode_error":
                decode_errors[(fields.get("error", ""), fields.get("header", ""))] += 1

    lines = [
        "# BLE Capture Summary",
        "",
        f"- entries: {len(entries)}",
        f"- packets: {packet_count}",
        f"- notes: {note_count}",
    ]

    if packet_uuids:
        lines.extend(["", "## Top Packet UUIDs"])
        for uuid, count in packet_uuids.most_common(6):
            lines.append(f"- `{uuid or '(none)'}`: {count}")

    if by_category:
        lines.extend(["", "## Note Categories"])
        for category, count in by_category.most_common():
            lines.append(f"- `{category}`: {count}")

    if protocol_labels:
        lines.extend(["", "## Decoded Protocol Labels"])
        for (label, reply), count in protocol_labels.most_common(12):
            flavor = "reply" if reply == "True" else "message"
            lines.append(f"- `{label}` ({flavor}): {count}")

    if unknown_packets:
        lines.extend(["", "## Unknown Packet Labels"])
        for (message, label), count in unknown_packets.most_common(12):
            lines.append(f"- `{message}` / `{label}`: {count}")

    if raw_events:
        lines.extend(["", "## Undecoded Event Payloads"])
        for (name, type_id, body_prefix), count in raw_events.most_common(12):
            label = name or f"type {type_id}"
            lines.append(f"- `{label}` body~`{body_prefix}`: {count}")

    if decode_errors:
        lines.extend(["", "## Decode Errors"])
        for (error, header), count in decode_errors.most_common(10):
            lines.append(f"- header `{header}`: {count} ({error})")

    recent = recent_entries(entries)
    if recent:
        lines.extend(["", "## Recent Timeline"])
        for entry in recent:
            unix_ms = entry.get("unix_ms", "")
            if entry.get("entry") == "packet":
                lines.append(
                    f"- `{unix_ms}` packet {entry.get('dir', '?')} {entry.get('uuid', '')} len={entry.get('len', 0)} hex={str(entry.get('hex', ''))[:48]}"
                )
            else:
                lines.append(
                    f"- `{unix_ms}` note {entry.get('category', '')}: {entry.get('message', '')}"
                )

    return "\n".join(lines) + "\n"


def main():
    base = Path("/Users/benjaminfaershtein/Documents/FieldHT/.ble-captures")
    base.mkdir(parents=True, exist_ok=True)
    device_id = detect_connected_device_id()
    if not device_id:
        print("No connected iPhone was detected for BLE capture ingest.", file=sys.stderr)
        sys.exit(1)

    copied_any = False
    local_files = []
    for label, remote in REMOTE_FILES:
        dest = base / f"{label}.jsonl"
        if copy_from_device(device_id, remote, dest):
            copied_any = True
            local_files.append(dest)

    if not copied_any:
        print("No capture files could be copied from the connected iPhone.", file=sys.stderr)
        sys.exit(1)

    entries = []
    for file in local_files:
        entries.extend(load_entries(file))

    report = summarize(entries)
    report_path = base / "latest_report.md"
    report_path.write_text(report)
    print(f"Device: {device_id}")
    print(f"Bundle: {BUNDLE_ID}")
    print(f"Report: {report_path}")
    print()
    print(report, end="")


if __name__ == "__main__":
    main()
