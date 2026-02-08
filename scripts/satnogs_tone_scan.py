#!/usr/bin/env python3

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, asdict
from typing import Any, Dict, Iterable, List, Optional, Tuple


_TONE_WORD_RE = re.compile(r"(?i)\b(ctcss|pl|tone|dcs)\b")
_NO_TONE_RE = re.compile(
    r"(?i)\b(?:no|without)\s+(?:ctcss|pl|tone)\b|\bcarrier\s+squelch\b|\bcsq\b"
)

# Common free-form formats:
# - "CTCSS 67.0 Hz" / "CTCSS 67.0Hz" / "CTCSS:67.0"
# - "(PL 88.5Hz)" / "67.0 PL" / "PL 88.5"
# - "Tone 67.0" / "Tone: 67.0 Hz"
_CTCSS_VALUE_PATTERNS = [
    re.compile(r"(?i)\bctcss\b\s*[:=]?\s*([0-9]{2,3}(?:\.[0-9])?)\s*(?:hz)?"),
    re.compile(r"(?i)\bpl\b\s*[:=]?\s*([0-9]{2,3}(?:\.[0-9])?)\s*(?:hz)?"),
    re.compile(r"(?i)\btone\b\s*[:=]?\s*([0-9]{2,3}(?:\.[0-9])?)\s*(?:hz)?"),
    re.compile(r"(?i)\b([0-9]{2,3}(?:\.[0-9])?)\s*(?:hz)?\s*\bpl\b"),
]

# DCS patterns (less common in SatNOGS transmitter descriptions but cheap to detect)
_DCS_PATTERNS = [
    re.compile(r"(?i)\bdcs\b\s*[:=]?\s*([0-9]{2,4})\b"),
    re.compile(r"(?i)\b([0-9]{2,4})\s*\bdcs\b"),
]


def _find_norad(obj: Any) -> Optional[int]:
    if isinstance(obj, dict):
        for k in ("norad_cat_id", "norad", "norad_id"):
            v = obj.get(k)
            if isinstance(v, int):
                return v
            if isinstance(v, str) and v.isdigit():
                return int(v)

        sat = obj.get("satellite")
        if isinstance(sat, dict):
            for k in ("norad_cat_id", "norad", "norad_id"):
                v = sat.get(k)
                if isinstance(v, int):
                    return v
                if isinstance(v, str) and v.isdigit():
                    return int(v)
    return None


def _classify_direction(text: str, match_span: Tuple[int, int]) -> Optional[str]:
    # Heuristic: look around the match for UL/DL/RX/TX hints.
    start, end = match_span
    lo = max(0, start - 30)
    hi = min(len(text), end + 30)
    ctx = text[lo:hi].lower()
    if re.search(r"\b(uplink|ul|tx|transmit|up-link)\b", ctx):
        return "tx"
    if re.search(r"\b(downlink|dl|rx|receive|down-link)\b", ctx):
        return "rx"
    return None


@dataclass(frozen=True)
class ToneMention:
    kind: str  # "ctcss" or "dcs" or "none"
    value: Optional[float]  # Hz for ctcss; numeric code for dcs (stored as float for simplicity)
    direction: Optional[str]  # "rx" | "tx" | None
    raw: str


def parse_tone_mentions(text: str) -> List[ToneMention]:
    if not text:
        return []

    mentions: List[ToneMention] = []

    if _NO_TONE_RE.search(text):
        mentions.append(ToneMention(kind="none", value=None, direction=None, raw="no/without tone"))

    for pat in _CTCSS_VALUE_PATTERNS:
        for m in pat.finditer(text):
            raw = m.group(0)
            try:
                hz = float(m.group(1))
            except ValueError:
                continue
            direction = _classify_direction(text, m.span())
            mentions.append(ToneMention(kind="ctcss", value=hz, direction=direction, raw=raw))

    for pat in _DCS_PATTERNS:
        for m in pat.finditer(text):
            raw = m.group(0)
            try:
                code = float(m.group(1))
            except ValueError:
                continue
            direction = _classify_direction(text, m.span())
            mentions.append(ToneMention(kind="dcs", value=code, direction=direction, raw=raw))

    # Dedupe while preserving order.
    seen = set()
    out: List[ToneMention] = []
    for mm in mentions:
        key = (mm.kind, mm.value, mm.direction, mm.raw.lower())
        if key in seen:
            continue
        seen.add(key)
        out.append(mm)
    return out


def _iter_json(obj: Any, path: str = "$") -> Iterable[Tuple[str, Any]]:
    yield (path, obj)
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield from _iter_json(v, f"{path}.{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from _iter_json(v, f"{path}[{i}]")


def _scan_other_fields(obj: Any) -> List[Dict[str, str]]:
    hits: List[Dict[str, str]] = []
    if not isinstance(obj, dict):
        return hits

    # Scan values.
    for path, node in _iter_json(obj):
        if path.endswith(".description"):
            continue
        if isinstance(node, str):
            if _TONE_WORD_RE.search(node) or _NO_TONE_RE.search(node):
                hits.append({"path": path, "value": node})

    # Scan keys.
    for path, node in _iter_json(obj):
        if not isinstance(node, dict):
            continue
        for k in node.keys():
            if isinstance(k, str) and _TONE_WORD_RE.search(k):
                hits.append({"path": f"{path}.{k}", "value": f"<key:{k}>"})

    return hits


def scan_file(file_path: str) -> Dict[str, Any]:
    with open(file_path, "rb") as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError("Expected a JSON array")

    grouped: Dict[str, List[Dict[str, Any]]] = {}

    for obj in data:
        if not isinstance(obj, dict):
            continue

        desc = obj.get("description")
        if not isinstance(desc, str):
            continue
        if not (_TONE_WORD_RE.search(desc) or _NO_TONE_RE.search(desc)):
            continue

        norad = _find_norad(obj)
        norad_key = str(norad) if norad is not None else "None"
        uuid = obj.get("uuid") or obj.get("id")

        entry = {
            "norad_cat_id": norad,
            "uuid": uuid,
            "description": desc,
            "uplink_low": obj.get("uplink_low"),
            "downlink_low": obj.get("downlink_low"),
            "tone_mentions": [asdict(m) for m in parse_tone_mentions(desc)],
            "other_tone_fields": _scan_other_fields(obj),
        }
        grouped.setdefault(norad_key, []).append(entry)

    return {
        "file": file_path,
        "by_norad": grouped,
    }


def _print_human(report: Dict[str, Any]) -> None:
    print(f"FILE: {report['file']}")
    by_norad = report["by_norad"]
    if not by_norad:
        print("  (no matches)")
        return

    for norad in sorted(by_norad.keys(), key=lambda x: (x == "None", x)):
        print(f"  NORAD: {norad}")
        for e in by_norad[norad]:
            print(f"    - uuid: {e.get('uuid')}")
            print(f"      uplink_low: {e.get('uplink_low')}")
            print(f"      downlink_low: {e.get('downlink_low')}")
            d = (e.get("description") or "").replace("\n", "\\n")
            print(f"      description: {d}")

            mentions = e.get("tone_mentions") or []
            if mentions:
                pretty = []
                for m in mentions:
                    if m["kind"] == "ctcss" and m["value"] is not None:
                        dv = f"{m['value']} Hz"
                    elif m["kind"] == "dcs" and m["value"] is not None:
                        dv = f"{int(m['value'])}"
                    else:
                        dv = "none"
                    dir_s = f" {m['direction']}" if m.get("direction") else ""
                    pretty.append(f"{m['kind']}{dir_s}={dv}")
                print("      parsed: " + ", ".join(pretty))

            other = e.get("other_tone_fields") or []
            if other:
                print("      other_tone_fields:")
                for h in other[:10]:
                    v = (h.get("value") or "").replace("\n", "\\n")
                    if len(v) > 200:
                        v = v[:200] + "…"
                    print(f"        * {h.get('path')}: {v}")
                if len(other) > 10:
                    print(f"        * (+{len(other) - 10} more)")


def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser(description="Scan SatNOGS transmitter JSON arrays for tone/CTCSS/PL mentions")
    ap.add_argument("files", nargs="+", help="One or more JSON files (each a JSON array of transmitters)")
    ap.add_argument("--json", action="store_true", help="Output machine-readable JSON")
    args = ap.parse_args(argv)

    reports = []
    for fp in args.files:
        try:
            reports.append(scan_file(fp))
        except Exception as e:
            print(f"ERROR: {fp}: {e}", file=sys.stderr)

    if args.json:
        json.dump({"reports": reports}, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 0

    for r in reports:
        _print_human(r)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
