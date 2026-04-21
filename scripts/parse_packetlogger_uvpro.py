#!/usr/bin/env python3
import argparse
import subprocess
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


BASIC_COMMANDS = {
    1: "getDevID",
    4: "getDevInfo",
    5: "readStatus",
    6: "registerNotification",
    9: "eventNotification",
    10: "readSettings",
    11: "writeSettings",
    13: "readRFCh",
    20: "getHTStatus",
    21: "setHTOnOff",
    22: "getVolume",
    23: "setVolume",
    24: "radioGetStatus",
    32: "setPosition",
    33: "readBSSSettings",
    34: "writeBSSSettings",
    35: "freqModeSetPar",
    36: "freqModeGetStatus",
    37: "readRDA1846S_AGC",
    39: "readFreqRange",
    44: "setHL",
    45: "setDID",
    46: "setIBA",
    47: "getIBA",
    48: "setTrustedDeviceName",
    49: "setVOC",
    50: "getVOC",
    51: "setPhoneStatus",
    52: "readRFStatus",
    53: "playTone",
    55: "getPF",
    56: "setPF",
    57: "rxData",
    58: "writeRegionCh",
    59: "writeRegionName",
    60: "setRegion",
    61: "setPP_ID",
    62: "getPP_ID",
    63: "readAdvancedSettings2",
    64: "writeAdvancedSettings2",
    65: "unlock",
    66: "doProgFunc",
    67: "setMSG",
    68: "getMSG",
    69: "bleConnParam",
    70: "setTime",
    71: "setAPRSPath",
    72: "getAPRSPath",
    73: "readRegionName",
    74: "setDevID",
    75: "getPFActions",
    76: "getPosition",
    77: "satModeSetInfo",
}

EVENT_TYPES = {
    1: "htStatusChanged",
    2: "dataRxd",
    3: "newInquiryData",
    4: "restoreFactorySettings",
    5: "htChChanged",
    6: "htSettingsChanged",
    7: "ringingStopped",
    8: "radioStatusChanged",
    9: "userAction",
    10: "systemEvent",
    11: "bssSettingsChanged",
    12: "dataTxd",
    13: "positionChanged",
}

PF_ACTIONS = {
    0: "invalid",
    1: "short",
    2: "long",
    3: "veryLong",
    4: "double",
    5: "repeat",
    6: "lowToHigh",
    7: "highToLow",
    8: "shortSingle",
    9: "longRelease",
    10: "veryLongRelease",
    11: "veryVeryLong",
    12: "veryVeryLongRelease",
    13: "triple",
}

PF_EFFECTS = {
    0: "Disable",
    1: "Alarm",
    2: "Alarm and Mute",
    3: "Toggle Standby",
    4: "Toggle Radio TX",
    5: "Toggle TX Power",
    6: "Toggle FM",
    7: "Previous Channel",
    8: "Next Channel",
    9: "T-Call",
    10: "Previous Region",
    11: "Next Region",
    12: "Toggle Channel Scan",
    13: "Main PTT",
    14: "Sub PTT",
    15: "Toggle Monitor",
    16: "BT Pairing",
    17: "Toggle Double Channel",
    18: "Toggle A/B Channel",
    19: "Send Location",
    20: "One Click Link",
    21: "Volume Down",
    22: "Volume Up",
    23: "Toggle Mute",
}

POWER_STATUS_TYPES = {
    1: "batteryLevel",
    2: "batteryVoltage",
    3: "rcBatteryLevel",
    4: "batteryPercent",
}


@dataclass
class ProtocolFrame:
    index: int
    connection_handle: int
    att_opcode: int
    att_handle: int
    command_group: int
    command: int
    is_reply: bool
    body: bytes

    @property
    def command_name(self) -> str:
        if self.command_group == 2:
            return BASIC_COMMANDS.get(self.command, f"basic.{self.command}")
        return f"group{self.command_group}.{self.command}"


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def detect_live_pklg() -> Path | None:
    result = run(["lsof", "-c", "PacketLogger"])
    if result.returncode == 0:
        for line in result.stdout.splitlines():
            if ".pklg" in line:
                parts = line.split()
                if parts:
                    path = Path(parts[-1])
                    if path.suffix == ".pklg" and path.exists():
                        return path

    candidates = sorted(
        Path("/Users/benjaminfaershtein").glob("*.pklg"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    return candidates[0] if candidates else None


def iter_pklg_records(path: Path) -> Iterable[bytes]:
    blob = path.read_bytes()
    pos = 0
    while pos + 4 <= len(blob):
        # PacketLogger stores record lengths as little-endian 32-bit integers.
        record_len = int.from_bytes(blob[pos : pos + 4], "little")
        if record_len <= 0 or pos + 4 + record_len > len(blob):
            break
        yield blob[pos + 4 : pos + 4 + record_len]
        pos += 4 + record_len


def bits_from_bytes(data: bytes) -> list[int]:
    bits: list[int] = []
    for byte in data:
        for i in range(8):
            bits.append(1 if byte & (1 << (7 - i)) else 0)
    return bits


def read_bits(bits: list[int], pos: int, count: int) -> tuple[int, int]:
    value = 0
    for i in range(count):
        value = (value << 1) | bits[pos + i]
    return value, pos + count


def decode_device_info(data: bytes) -> dict[str, object]:
    bits = bits_from_bytes(data)
    pos = 0
    vendor_id, pos = read_bits(bits, pos, 8)
    product_id, pos = read_bits(bits, pos, 16)
    hardware_version, pos = read_bits(bits, pos, 8)
    firmware_version, pos = read_bits(bits, pos, 16)
    supports_radio, pos = read_bits(bits, pos, 1)
    supports_medium_power, pos = read_bits(bits, pos, 1)
    fixed_location_speaker_volume, pos = read_bits(bits, pos, 1)
    not_support_soft_power_ctrl, pos = read_bits(bits, pos, 1)
    have_no_speaker, pos = read_bits(bits, pos, 1)
    have_hm_speaker, pos = read_bits(bits, pos, 1)
    region_count, pos = read_bits(bits, pos, 6)
    supports_noaa, pos = read_bits(bits, pos, 1)
    supports_gmrs, pos = read_bits(bits, pos, 1)
    supports_vfo, pos = read_bits(bits, pos, 1)
    supports_dmr, pos = read_bits(bits, pos, 1)
    channel_count, pos = read_bits(bits, pos, 8)
    frequency_range_count, pos = read_bits(bits, pos, 4)
    support_noise_reduction, pos = read_bits(bits, pos, 1)
    support_smart_beacon, pos = read_bits(bits, pos, 1)
    _pad, pos = read_bits(bits, pos, 2)

    return {
        "vendorID": vendor_id,
        "productID": product_id,
        "hardwareVersion": hardware_version,
        "firmwareVersionRaw": firmware_version,
        "firmwareVersionDisplay": f"{firmware_version / 100.0:.2f}",
        "supportsRadio": bool(supports_radio),
        "supportsMediumPower": bool(supports_medium_power),
        "fixedLocationSpeakerVolume": bool(fixed_location_speaker_volume),
        "supportsSoftwarePowerControl": not bool(not_support_soft_power_ctrl),
        "hasSpeaker": not bool(have_no_speaker),
        "hasHandMicrophoneSpeaker": bool(have_hm_speaker),
        "regionCount": region_count,
        "supportsNOAA": bool(supports_noaa),
        "supportsGMRS": bool(supports_gmrs),
        "supportsVFO": bool(supports_vfo),
        "supportsDMR": bool(supports_dmr),
        "channelCount": channel_count,
        "frequencyRangeCount": frequency_range_count,
        "supportNoiseReduction": bool(support_noise_reduction),
        "supportSmartBeacon": bool(support_smart_beacon),
    }


def decode_power_status(data: bytes) -> dict[str, object]:
    if len(data) < 3:
        return {"raw": data.hex()}
    kind = int.from_bytes(data[:2], "big")
    name = POWER_STATUS_TYPES.get(kind, f"unknown({kind})")
    if kind == 2 and len(data) >= 4:
        return {"type": name, "voltageV": int.from_bytes(data[2:4], "big") / 1000.0}
    if len(data) >= 3:
        return {"type": name, "value": data[2]}
    return {"type": name}


def decode_status(data: bytes) -> dict[str, object]:
    bits = bits_from_bytes(data)
    pos = 0
    is_power_on, pos = read_bits(bits, pos, 1)
    is_in_tx, pos = read_bits(bits, pos, 1)
    is_sq, pos = read_bits(bits, pos, 1)
    is_in_rx, pos = read_bits(bits, pos, 1)
    double_channel, pos = read_bits(bits, pos, 2)
    is_scan, pos = read_bits(bits, pos, 1)
    is_radio, pos = read_bits(bits, pos, 1)
    curr_ch_lower, pos = read_bits(bits, pos, 4)
    is_gps_locked, pos = read_bits(bits, pos, 1)
    is_hfp_connected, pos = read_bits(bits, pos, 1)
    is_aoc_connected, pos = read_bits(bits, pos, 1)
    _reserved, pos = read_bits(bits, pos, 1)

    decoded: dict[str, object] = {
        "isPowerOn": bool(is_power_on),
        "isInTx": bool(is_in_tx),
        "isSq": bool(is_sq),
        "isInRx": bool(is_in_rx),
        "doubleChannelRaw": double_channel,
        "isScan": bool(is_scan),
        "isRadio": bool(is_radio),
        "currChIDLower": curr_ch_lower,
        "isGPSLocked": bool(is_gps_locked),
        "isHFPConnected": bool(is_hfp_connected),
        "isAOCConnected": bool(is_aoc_connected),
    }

    if len(bits) - pos >= 16:
        rssi_raw, pos = read_bits(bits, pos, 4)
        curr_region, pos = read_bits(bits, pos, 6)
        curr_ch_upper, pos = read_bits(bits, pos, 4)
        _pad, pos = read_bits(bits, pos, 2)
        decoded["rssiRaw"] = rssi_raw
        decoded["currRegion"] = curr_region
        decoded["currChID"] = (curr_ch_upper << 4) | curr_ch_lower

    return decoded


def decode_pf(data: bytes) -> list[dict[str, object]]:
    bits = bits_from_bytes(data)
    pos = 8
    entries: list[dict[str, object]] = []
    while len(bits) - pos >= 16:
        button_id, pos = read_bits(bits, pos, 4)
        action_raw, pos = read_bits(bits, pos, 4)
        effect_raw, pos = read_bits(bits, pos, 8)
        entries.append(
            {
                "buttonID": button_id,
                "triggerRaw": action_raw,
                "trigger": PF_ACTIONS.get(action_raw, f"action{action_raw}"),
                "effectRaw": effect_raw,
                "effect": PF_EFFECTS.get(effect_raw, f"Unknown Action {effect_raw}"),
            }
        )
    return entries


def decode_pf_effect_table(data: bytes) -> list[dict[str, object]]:
    return [
        {
            "slot": index,
            "effectRaw": value,
            "effect": PF_EFFECTS.get(value, f"Unknown Action {value}"),
        }
        for index, value in enumerate(data)
    ]


def decode_pf_actions(data: bytes) -> list[dict[str, object]]:
    payload = data[1:] if data and data[0] == 0 else data
    return [
        {
            "effectRaw": value,
            "effect": PF_EFFECTS.get(value, f"Unknown Action {value}"),
        }
        for value in payload
    ]


def decode_event(data: bytes) -> dict[str, object]:
    if not data:
        return {"raw": ""}
    event_type = data[0]
    payload = data[1:]
    name = EVENT_TYPES.get(event_type, f"unknown({event_type})")
    decoded: dict[str, object] = {"type": event_type, "name": name, "raw": payload.hex()}
    if event_type in (1, 8):
        decoded["status"] = decode_status(payload)
    return decoded


def parse_protocol_frames(path: Path) -> list[ProtocolFrame]:
    frames: list[ProtocolFrame] = []
    for index, record in enumerate(iter_pklg_records(path)):
        payload = record[8:]
        if len(payload) < 10 or payload[0] not in (2, 3):
            continue
        connection_handle = int.from_bytes(payload[1:3], "little") & 0x0FFF
        l2cap_length = int.from_bytes(payload[5:7], "little")
        cid = int.from_bytes(payload[7:9], "little")
        if cid != 4 or len(payload) < 10:
            continue
        att_opcode = payload[9]
        if att_opcode not in (0x12, 0x1D, 0x1B, 0x52):
            continue

        content = payload[10 : 10 + l2cap_length - 1]
        if len(content) < 2:
            continue
        att_handle = int.from_bytes(content[:2], "little")
        value = content[2:]
        if len(value) < 4:
            continue

        command_group = int.from_bytes(value[:2], "big")
        if command_group not in (2, 10):
            continue
        command_word = int.from_bytes(value[2:4], "big")
        frames.append(
            ProtocolFrame(
                index=index,
                connection_handle=connection_handle,
                att_opcode=att_opcode,
                att_handle=att_handle,
                command_group=command_group,
                command=command_word & 0x7FFF,
                is_reply=bool(command_word & 0x8000),
                body=value[4:],
            )
        )
    return frames


def connection_score(frames: list[ProtocolFrame], connection_handle: int) -> tuple[int, int]:
    scoped = [frame for frame in frames if frame.connection_handle == connection_handle]
    commands = Counter(frame.command for frame in scoped)
    score = (
        commands[11] * 60
        + commands[25] * 60
        + commands[13] * 20
        + commands[24] * 15
        + commands[36] * 15
        + commands[5] * 40
        + commands[55] * 50
        + commands[75] * 50
        + commands[9] * 20
        + commands[4] * 10
        + len(scoped)
    )
    return score, len(scoped)


def prioritized_connections(frames: list[ProtocolFrame]) -> list[int]:
    handles = sorted({frame.connection_handle for frame in frames})
    return sorted(handles, key=lambda handle: connection_score(frames, handle), reverse=True)


def find_best_connection(frames: list[ProtocolFrame]) -> int | None:
    ordered = prioritized_connections(frames)
    return ordered[0] if ordered else None


def summarize_connection(frames: list[ProtocolFrame], connection_handle: int) -> str:
    scoped = [frame for frame in frames if frame.connection_handle == connection_handle]
    request_counts = Counter(frame.command_name for frame in scoped if not frame.is_reply)
    reply_counts = Counter(frame.command_name for frame in scoped if frame.is_reply)

    lines = [
        "# PacketLogger UV-PRO Summary",
        "",
        f"- connection handle: `0x{connection_handle:02x}`",
        f"- protocol frames: `{len(scoped)}`",
        f"- ATT write handle used by phone: `{format_handles(scoped, is_reply=False)}`",
        f"- ATT indication/notify handle from radio: `{format_handles(scoped, is_reply=True)}`",
    ]

    if request_counts:
        lines.extend(["", "## Requests"])
        for name, count in request_counts.most_common():
            lines.append(f"- `{name}`: {count}")

    if reply_counts:
        lines.extend(["", "## Replies"])
        for name, count in reply_counts.most_common():
            lines.append(f"- `{name}`: {count}")

    lines.extend(["", "## Key Findings"])
    lines.extend(key_findings(scoped))

    accessory_lines = accessory_findings(scoped)
    if accessory_lines:
        lines.extend(["", "## Accessory Findings"])
        lines.extend(accessory_lines)

    lines.extend(["", "## Timeline"])
    for line in timeline_lines(scoped[:80]):
        lines.append(line)

    return "\n".join(lines) + "\n"


def summarize_sessions(frames: list[ProtocolFrame], handles: list[int]) -> list[str]:
    lines = ["## Candidate Sessions"]
    for handle in handles:
        scoped = [frame for frame in frames if frame.connection_handle == handle]
        commands = Counter(frame.command_name for frame in scoped if not frame.is_reply)
        score, total = connection_score(frames, handle)
        lines.append(
            f"- `0x{handle:02x}` score=`{score}` frames=`{total}` top requests=`{', '.join(f'{name}:{count}' for name, count in commands.most_common(5))}`"
        )
    return lines


def format_handles(frames: list[ProtocolFrame], is_reply: bool) -> str:
    handles = Counter(frame.att_handle for frame in frames if frame.is_reply == is_reply)
    if not handles:
        return "n/a"
    return ", ".join(f"0x{handle:04x} ({count})" for handle, count in handles.most_common())


def key_findings(frames: list[ProtocolFrame]) -> list[str]:
    findings: list[str] = []

    dev_info = next((frame for frame in frames if frame.command == 4 and frame.is_reply), None)
    if dev_info:
        info = decode_device_info(dev_info.body[1:])
        findings.append(
            "- OEM app sees the same device info channel we use: "
            f"`firmware={info['firmwareVersionDisplay']}`, "
            f"`hasHandMicrophoneSpeaker={info['hasHandMicrophoneSpeaker']}`, "
            f"`supportsRadio={info['supportsRadio']}`"
        )

    power_reads = [frame for frame in frames if frame.command == 5]
    if power_reads:
        decoded_reads = [decode_power_status(frame.body[1:]) for frame in power_reads if frame.is_reply and len(frame.body) > 1]
        findings.append(
            "- OEM app explicitly polls radio power status using `readStatus`, including the RC battery path."
        )
        for item in decoded_reads:
            if item.get("type") == "rcBatteryLevel":
                findings.append(f"- Speaker-mic battery query reply: `{item}`")
            elif item.get("type") == "batteryVoltage":
                findings.append(f"- Radio voltage reply: `{item}`")
            elif item.get("type") == "batteryLevel":
                findings.append(f"- Radio battery reply: `{item}`")

    pf_frame = next((frame for frame in frames if frame.command == 55 and frame.is_reply), None)
    if pf_frame:
        entries = decode_pf(pf_frame.body)
        findings.append("- OEM app reads the current PF table from the radio; this capture did not show a separate speaker-mic-only PF table.")
        for entry in entries:
            findings.append(
                f"- PF button `{entry['buttonID']}` `{entry['trigger']}` -> `{entry['effect']}`"
            )

    event_frames = [frame for frame in frames if frame.command == 9 and not frame.is_reply]
    decoded_status_events = [
        decode_event(frame.body) for frame in event_frames if frame.body and frame.body[0] in (1, 8)
    ]
    if decoded_status_events:
        aoc_states = {event["status"]["isAOCConnected"] for event in decoded_status_events if "status" in event}
        hfp_states = {event["status"]["isHFPConnected"] for event in decoded_status_events if "status" in event}
        findings.append(
            "- Status notifications from the OEM app show speaker/audio state changes on the same event stream FieldHT already subscribes to."
        )
        findings.append(
            f"- Observed `isHFPConnected` states: `{sorted(hfp_states)}`; observed `isAOCConnected` states: `{sorted(aoc_states)}`"
        )
        if aoc_states == {False} and True in hfp_states:
            findings.append(
                "- In this capture the OEM app never saw `isAOCConnected=true`, even while HFP/audio was active. That matches the flaky AOC bit we have been fighting in FieldHT."
            )

    if not findings:
        findings.append("- No high-signal protocol frames were found in this capture.")
    return findings


def accessory_findings(frames: list[ProtocolFrame]) -> list[str]:
    findings: list[str] = []
    dev_info = next((frame for frame in frames if frame.command == 4 and frame.is_reply), None)
    if not dev_info:
        return findings

    info = decode_device_info(dev_info.body[1:])
    if info.get("supportsRadio") is not False:
        return findings

    findings.append(
        "- This session looks like a separate accessory peripheral, not the main radio: "
        f"`productID={info['productID']}`, `firmware={info['firmwareVersionDisplay']}`, "
        f"`supportsRadio={info['supportsRadio']}`."
    )

    pf_reply = next((frame for frame in frames if frame.command == 55 and frame.is_reply), None)
    if pf_reply:
        entries = decode_pf(pf_reply.body)
        findings.append("- Accessory PF table from `getPF`:")
        for entry in entries:
            findings.append(
                f"- slot `{entry['buttonID']}/{entry['trigger']}` -> `{entry['effect']}`"
            )

    actions_reply = next((frame for frame in frames if frame.command == 75 and frame.is_reply), None)
    if actions_reply:
        actions = decode_pf_actions(actions_reply.body)
        findings.append(
            "- Accessory-supported PF actions from `getPFActions`: "
            + ", ".join(f"`{item['effect']}`" for item in actions)
        )

    set_pf_requests = [frame for frame in frames if frame.command == 56 and not frame.is_reply]
    if set_pf_requests:
        findings.append("- Accessory `setPF` writes are effect-only 16-byte tables.")
        previous = None
        for index, frame in enumerate(set_pf_requests, start=1):
            table = decode_pf_effect_table(frame.body)
            pretty = ", ".join(item["effect"] for item in table)
            findings.append(f"- Write `{index}`: `{pretty}`")
            if previous is not None:
                changes = []
                for before, after in zip(previous, table):
                    if before["effectRaw"] != after["effectRaw"]:
                        changes.append(
                            f"slot {after['slot']} `{before['effect']}` -> `{after['effect']}`"
                        )
                if changes:
                    findings.append("- Diff vs previous write: " + ", ".join(changes))
            previous = table

    return findings


def timeline_lines(frames: list[ProtocolFrame]) -> list[str]:
    lines: list[str] = []
    for frame in frames:
        direction = "reply" if frame.is_reply else "request"
        summary = frame.body.hex()
        if frame.command == 4 and frame.is_reply:
            info = decode_device_info(frame.body[1:])
            summary = f"firmware={info['firmwareVersionDisplay']} hmSpeaker={info['hasHandMicrophoneSpeaker']}"
        elif frame.command == 5 and frame.is_reply:
            summary = str(decode_power_status(frame.body[1:]))
        elif frame.command == 55 and frame.is_reply:
            summary = ", ".join(
                f"btn{row['buttonID']} {row['trigger']} -> {row['effect']}" for row in decode_pf(frame.body)
            )
        elif frame.command == 56 and not frame.is_reply:
            summary = ", ".join(item["effect"] for item in decode_pf_effect_table(frame.body))
        elif frame.command == 75 and frame.is_reply:
            summary = ", ".join(item["effect"] for item in decode_pf_actions(frame.body))
        elif frame.command == 9 and not frame.is_reply:
            summary = str(decode_event(frame.body))
        lines.append(
            f"- `#{frame.index}` {direction} `{frame.command_name}` att=`0x{frame.att_handle:04x}` body=`{summary}`"
        )
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract UV-PRO protocol frames from a PacketLogger .pklg capture.")
    parser.add_argument("--input", type=Path, help="Path to a .pklg file. Defaults to the live PacketLogger file.")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("/Users/benjaminfaershtein/Documents/FieldHT/.ble-captures/latest-packetlogger-report.md"),
        help="Where to write the Markdown summary.",
    )
    args = parser.parse_args()

    source = args.input or detect_live_pklg()
    if not source or not source.exists():
        raise SystemExit("No PacketLogger .pklg file was found.")

    frames = parse_protocol_frames(source)
    connection_handle = find_best_connection(frames)
    if connection_handle is None:
        raise SystemExit(f"No UV-PRO protocol frames found in {source}")

    report = summarize_connection(frames, connection_handle)
    ordered = prioritized_connections(frames)
    session_lines = summarize_sessions(frames, ordered[:4])
    report = report.replace("## Key Findings", "\n".join(session_lines) + "\n\n## Key Findings", 1)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(report)

    print(f"source: {source}")
    print(f"report: {args.output}")
    print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
