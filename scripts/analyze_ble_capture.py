#!/usr/bin/env python3
import json
import sys
import argparse
from collections import Counter
from pathlib import Path


IMPORTANT_CATEGORIES = {
    "radio_connect_requested",
    "radio_connect_completed",
    "radio_connect_failed",
    "connect_attempt_started",
    "connect_scan_started",
    "connect_using_retrieved_peripheral",
    "connect_resume_existing",
    "connect",
    "service_discovery_started",
    "connect_ready",
    "selected_channels_hydrated",
    "background_hydration_complete",
    "background_hydration_failed",
    "radio_transport_disconnected",
    "disconnect",
    "radio_reconnect_started",
    "radio_reconnect_attempt",
    "radio_reconnect_retry_scheduled",
    "radio_reconnect_completed",
    "radio_reconnect_stopped",
    "connection_health_started",
    "connection_health",
    "connect_timeout",
    "connect_failed",
    "central_state",
    "app_scene_phase",
}


def load_entries(path: Path):
    entries = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError as exc:
                print(f"Skipping invalid JSON on line {line_number}: {exc}", file=sys.stderr)
    return entries


def load_all_entries(paths: list[Path]):
    entries = []
    for path in paths:
        if not path.exists():
            print(f"File not found: {path}", file=sys.stderr)
            raise SystemExit(1)
        entries.extend(load_entries(path))
    return sorted(entries, key=lambda entry: entry.get("unix_ms", 0))


def relative_ms(entry_ms: int, first_ms: int) -> int:
    return entry_ms - first_ms


def parse_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def is_connection_interruption(entry):
    category = entry.get("category")
    fields = entry.get("fields", {})

    if category == "disconnect":
        return fields.get("ready") == "true" and fields.get("requested") != "true"

    return category in {
        "radio_transport_disconnected",
        "radio_connect_failed",
        "connect_timeout",
        "connect_failed",
    }


def connection_health_sessions(note_entries):
    sessions = []
    current = None

    for entry in sorted(note_entries, key=lambda item: item.get("unix_ms", 0)):
        category = entry.get("category")
        fields = entry.get("fields", {})

        if category == "connection_health_started":
            if current is not None:
                sessions.append(current)
            current = {
                "started_ms": entry.get("unix_ms", 0),
                "heartbeats": 0,
                "max_uptime_ms": 0,
                "last_heartbeat_ms": 0,
                "max_heartbeat_gap_ms": 0,
                "backgrounded": False,
                "scene_phases": Counter(),
                "interrupted": False,
                "interruption": None,
            }
            continue

        if current is None:
            continue

        if category == "app_scene_phase":
            phase = fields.get("phase", "unknown")
            current["scene_phases"][phase] += 1
            if phase != "active":
                current["backgrounded"] = True
            continue

        if category == "connection_health" and fields.get("transport_ready") != "false":
            uptime_ms = parse_int(fields.get("uptime_ms"))
            heartbeat_ms = entry.get("unix_ms", 0)
            if current["last_heartbeat_ms"]:
                current["max_heartbeat_gap_ms"] = max(
                    current["max_heartbeat_gap_ms"],
                    heartbeat_ms - current["last_heartbeat_ms"],
                )
            current["heartbeats"] += 1
            current["max_uptime_ms"] = max(current["max_uptime_ms"], uptime_ms)
            current["last_heartbeat_ms"] = heartbeat_ms
            continue

        if is_connection_interruption(entry):
            current["interrupted"] = True
            current["interruption"] = entry
            sessions.append(current)
            current = None

    if current is not None:
        sessions.append(current)

    return sessions


def summarize(
    entries,
    prove_minutes: float | None = None,
    timeline_limit: int = 200,
    max_heartbeat_gap_seconds: float = 30.0,
):
    if not entries:
        print("No entries found.")
        return

    first_ms = min(entry.get("unix_ms", 0) for entry in entries)
    note_entries = [entry for entry in entries if entry.get("entry") == "note"]
    packet_entries = [entry for entry in entries if entry.get("entry") == "packet"]

    category_counts = Counter(entry.get("category", "unknown") for entry in note_entries)

    print("BLE Capture Summary")
    print(f"Entries: {len(entries)} total, {len(note_entries)} notes, {len(packet_entries)} packets")
    print(f"Time span: {max(entry.get('unix_ms', first_ms) for entry in entries) - first_ms} ms")
    print()

    print("Key category counts:")
    for category, count in sorted(category_counts.items()):
        if category in IMPORTANT_CATEGORIES:
            print(f"  {category}: {count}")
    print()

    important_timeline = [
        entry
        for entry in note_entries
        if entry.get("category", "unknown") in IMPORTANT_CATEGORIES
    ]
    if timeline_limit > 0 and len(important_timeline) > timeline_limit:
        hidden = len(important_timeline) - timeline_limit
        important_timeline = important_timeline[-timeline_limit:]
        print(f"Timeline: last {timeline_limit} important notes ({hidden} older hidden)")
    else:
        print("Timeline:")

    for entry in important_timeline:
        category = entry.get("category", "unknown")
        fields = entry.get("fields", {})
        payload = ", ".join(f"{key}={value}" for key, value in sorted(fields.items()))
        at_ms = relative_ms(entry.get("unix_ms", first_ms), first_ms)
        if payload:
            print(f"  +{at_ms:>7} ms  {category}: {payload}")
        else:
            print(f"  +{at_ms:>7} ms  {category}")
    print()

    ready_times = [
        int(entry.get("fields", {}).get("total_ms", "0"))
        for entry in note_entries
        if entry.get("category") == "connect_ready"
    ]
    hydration_times = [
        int(entry.get("fields", {}).get("elapsed_ms", "0"))
        for entry in note_entries
        if entry.get("category") == "background_hydration_complete"
    ]
    connected_durations = [
        int(entry.get("fields", {}).get("connected_ms", "0"))
        for entry in note_entries
        if entry.get("category") == "disconnect"
    ]
    heartbeat_uptimes = [
        parse_int(entry.get("fields", {}).get("uptime_ms"))
        for entry in note_entries
        if entry.get("category") == "connection_health"
        and entry.get("fields", {}).get("transport_ready") != "false"
    ]
    health_sessions = connection_health_sessions(note_entries)

    if ready_times:
        print(
            "Connect ready timings (ms): "
            f"count={len(ready_times)} min={min(ready_times)} max={max(ready_times)} avg={sum(ready_times) // len(ready_times)}"
        )
    if hydration_times:
        print(
            "Background hydration timings (ms): "
            f"count={len(hydration_times)} min={min(hydration_times)} max={max(hydration_times)} avg={sum(hydration_times) // len(hydration_times)}"
        )
    if connected_durations:
        print(
            "Connected durations before disconnect (ms): "
            f"count={len(connected_durations)} min={min(connected_durations)} max={max(connected_durations)} avg={sum(connected_durations) // len(connected_durations)}"
        )
    if heartbeat_uptimes:
        print(
            "Connection health uptime (ms): "
            f"heartbeats={len(heartbeat_uptimes)} max={max(heartbeat_uptimes)}"
        )
    if health_sessions:
        latest_session = health_sessions[-1]
        print(
            "Latest health session: "
            f"heartbeats={latest_session['heartbeats']} "
            f"max_uptime_ms={latest_session['max_uptime_ms']} "
            f"max_heartbeat_gap_ms={latest_session['max_heartbeat_gap_ms']} "
            f"backgrounded={latest_session['backgrounded']} "
            f"interrupted={latest_session['interrupted']}"
        )
        if latest_session["scene_phases"]:
            phases = ", ".join(
                f"{phase}={count}"
                for phase, count in sorted(latest_session["scene_phases"].items())
            )
            print(f"Latest health session scene phases: {phases}")

    if prove_minutes is not None:
        required_ms = int(prove_minutes * 60_000)
        max_gap_ms = int(max_heartbeat_gap_seconds * 1000)
        latest_session = health_sessions[-1] if health_sessions else None
        max_uptime_ms = latest_session["max_uptime_ms"] if latest_session else 0
        interrupted = latest_session["interrupted"] if latest_session else True
        heartbeat_gap_ms = latest_session["max_heartbeat_gap_ms"] if latest_session else 0
        print()
        print(f"Proof gate: uninterrupted connection >= {required_ms} ms")
        if not latest_session:
            print("FAIL: no connection health session found")
            raise SystemExit(3)
        if max_uptime_ms >= required_ms and not interrupted and heartbeat_gap_ms <= max_gap_ms:
            print(f"PASS: latest health session reached {max_uptime_ms} ms without an interruption")
        else:
            print(
                "FAIL: latest health session "
                f"max_uptime_ms={max_uptime_ms} "
                f"max_heartbeat_gap_ms={heartbeat_gap_ms} "
                f"allowed_gap_ms={max_gap_ms} "
                f"backgrounded={latest_session['backgrounded']} "
                f"interrupted={interrupted}"
            )
            raise SystemExit(3)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "capture",
        nargs="+",
        help="Path(s) to fieldht_ble_capture.jsonl files. Pass rotated files first, current files last.",
    )
    parser.add_argument(
        "--prove-minutes",
        type=float,
        default=None,
        help="Fail unless capture proves this many continuous connected minutes",
    )
    parser.add_argument(
        "--timeline-limit",
        type=int,
        default=200,
        help="Print only the last N important timeline notes. Use 0 for the full timeline.",
    )
    parser.add_argument(
        "--max-heartbeat-gap-seconds",
        type=float,
        default=30.0,
        help="Fail proof if the latest health session has a heartbeat gap above this many seconds.",
    )
    args = parser.parse_args()

    paths = [Path(capture).expanduser() for capture in args.capture]
    summarize(
        load_all_entries(paths),
        prove_minutes=args.prove_minutes,
        timeline_limit=args.timeline_limit,
        max_heartbeat_gap_seconds=args.max_heartbeat_gap_seconds,
    )


if __name__ == "__main__":
    main()
