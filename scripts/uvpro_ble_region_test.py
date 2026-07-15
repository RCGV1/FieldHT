#!/usr/bin/env python3

"""UV-PRO BLE region-name tester.

Purpose
  - Connect to the UV-PRO BLE service
  - Read all region names
  - Run rename experiments to determine whether cmd 59 targets by:
      (A) explicit regionID in body, or
      (B) current/active region (requires cmd 60 setRegion before write)

Prereqs
  - macOS with Bluetooth enabled
  - Close the FieldHT app while running (radio typically allows one BLE client).
  - Python 3.9+
  - pip install bleak

Examples
  - Scan and pick device:
      python3 scripts/uvpro_ble_region_test.py --scan

  - Read region names (auto-connect to first UV-PRO service advertiser):
      python3 scripts/uvpro_ble_region_test.py --read

  - Run the full matrix experiment on region 1, then restore original names:
      python3 scripts/uvpro_ble_region_test.py --matrix 1

  - Rename region 2 to TEST (tries current-region path first, then fallback):
      python3 scripts/uvpro_ble_region_test.py --rename 2 TEST
"""

from __future__ import annotations

import argparse
import asyncio
import dataclasses
import traceback
import types
from typing import Any, Dict, List, Optional, Tuple


RADIO_SERVICE_UUID = "00001100-D102-11E1-9B23-00025B00A5A5".lower()
RADIO_WRITE_UUID = "00001101-D102-11E1-9B23-00025B00A5A5".lower()
RADIO_INDICATE_UUID = "00001102-D102-11E1-9B23-00025B00A5A5".lower()


class BitReader:
    def __init__(self, data: bytes):
        self._data = data
        self._bitpos = 0

    def remaining(self) -> int:
        return len(self._data) * 8 - self._bitpos

    def read_int(self, nbits: int) -> int:
        if nbits < 0:
            raise ValueError("nbits must be >= 0")
        if self._bitpos + nbits > len(self._data) * 8:
            raise ValueError("end of stream")
        v = 0
        for _ in range(nbits):
            byte_i = self._bitpos // 8
            bit_i = self._bitpos % 8
            # MSB-first bit order
            bit = (self._data[byte_i] >> (7 - bit_i)) & 1
            v = (v << 1) | bit
            self._bitpos += 1
        return v

    def read_bool(self) -> bool:
        return self.read_int(1) != 0

    def read_bytes(self, nbytes: int) -> bytes:
        if nbytes < 0:
            raise ValueError("nbytes must be >= 0")
        # Byte reads must be byte-aligned
        if self._bitpos % 8 != 0:
            raise ValueError("not byte-aligned")
        start = self._bitpos // 8
        end = start + nbytes
        if end > len(self._data):
            raise ValueError("end of stream")
        self._bitpos += nbytes * 8
        return self._data[start:end]


@dataclasses.dataclass(frozen=True)
class ProtoMsg:
    group: int
    is_reply: bool
    command: int
    body: bytes


def _hex(b: bytes) -> str:
    return b.hex()


def encode_message(group: int, command: int, body: bytes, is_reply: bool = False) -> bytes:
    # Matches FieldHT BitStream packing:
    # - group: 16 bits
    # - isReply: 1 bit (top bit of next 16)
    # - command: 15 bits
    if group < 0 or group > 0xFFFF:
        raise ValueError("group out of range")
    if command < 0 or command > 0x7FFF:
        raise ValueError("command out of range")
    hdr0 = group.to_bytes(2, "big")
    cmd_field = command | (0x8000 if is_reply else 0)
    hdr1 = cmd_field.to_bytes(2, "big")
    return hdr0 + hdr1 + body


def decode_message(data: bytes) -> ProtoMsg:
    if len(data) < 4:
        raise ValueError("message too short")
    group = int.from_bytes(data[0:2], "big")
    cmd_field = int.from_bytes(data[2:4], "big")
    is_reply = (cmd_field & 0x8000) != 0
    command = cmd_field & 0x7FFF
    body = data[4:]
    return ProtoMsg(group=group, is_reply=is_reply, command=command, body=body)


def decode_reply_status(body: bytes) -> int:
    if not body:
        raise ValueError("empty reply body")
    return body[0]


def decode_region_name_reply(body: bytes) -> Tuple[int, int, str, bytes]:
    """Returns (status, region_id_echo, name_str, name_raw)."""
    if len(body) < 2:
        raise ValueError(f"readRegionName reply too short: {len(body)}")
    status = body[0]
    region_id = body[1]
    name_raw = body[2:]
    # Firmware appears to return 10 name bytes; tolerate longer/padded.
    name = name_raw.split(b"\x00", 1)[0].decode("utf-8", errors="replace")
    return status, region_id, name, name_raw


def encode_name10(name: str) -> bytes:
    b = name.encode("utf-8", errors="replace")
    b = b[:10]
    b = b + (b"\x00" * (10 - len(b)))
    return b


def encode_read_region_name(region_id: int) -> bytes:
    return bytes([region_id & 0xFF])


def encode_set_region(region_id: int) -> bytes:
    return bytes([region_id & 0xFF])


def encode_write_region_name_id(region_id: int, name: str) -> bytes:
    return bytes([region_id & 0xFF]) + encode_name10(name)


def encode_write_region_name_current(name: str) -> bytes:
    return encode_name10(name)


def decode_dev_info_region_count(body: bytes) -> int:
    """Decode just enough of DevInfo to get regionCount.

    Reply body includes reply_status byte, then bit-packed fields.
    Field layout matches FieldHT/Protocol/ProtocolDecoder.swift decodeDeviceInfo.
    """
    status = decode_reply_status(body)
    if status != 0:
        raise ValueError(f"getDevInfo failed status={status}")
    r = BitReader(body[1:])
    _vendor = r.read_int(8)
    _product = r.read_int(16)
    _hw = r.read_int(8)
    _soft = r.read_int(16)
    _support_radio = r.read_bool()
    _support_med_power = r.read_bool()
    _fixed_loc_spk_vol = r.read_bool()
    _not_support_soft_pwr = r.read_bool()
    _have_no_spk = r.read_bool()
    _have_hm_spk = r.read_bool()
    region_count = r.read_int(6)
    return region_count


async def discover_services(client: Any) -> Any:
    """Return Bleak service collection across supported Bleak releases."""
    try:
        return client.services
    except Exception:
        legacy_getter = getattr(client, "get_services", None)
        if legacy_getter is not None:
            return await legacy_getter()
        backend = getattr(client, "_backend", None)
        getter = getattr(backend, "_get_services", None)
        if getter is None:
            raise
        return await getter()


async def discover_services_force(client: Any) -> Any:
    """Force a fresh service discovery (bypasses cached client.services)."""
    backend = getattr(client, "_backend", None)
    if backend is None:
        return await discover_services(client)
    try:
        backend.services = None
    except Exception:
        pass
    getter = getattr(backend, "_get_services", None)
    if getter is None:
        return await discover_services(client)
    return await getter()


class UVProBle:
    def __init__(self, client, write_uuid: str, indicate_uuid: str, verbose: bool):
        self._client = client
        self._write_uuid = write_uuid
        self.indicate_uuid = indicate_uuid
        self._verbose = verbose

        self._pending: Dict[Tuple[int, int], asyncio.Future] = {}
        self._lock = asyncio.Lock()
        self._rx_count = 0

    def _on_notify(self, _char, data: bytearray):
        b = bytes(data)
        self._rx_count += 1
        try:
            msg = decode_message(b)
        except Exception as e:
            print(f"[BLE-RX] undecodable ({len(b)} bytes): {_hex(b)} ({e})")
            return

        if self._verbose:
            print(f"[BLE-RX] Raw ({len(b)} bytes): {_hex(b)}")
            print(
                f"[BLE-RX] Decoded -> Reply: {msg.is_reply}, Grp: {msg.group}, Cmd: {msg.command}, Body: {_hex(msg.body)}"
            )

        if not msg.is_reply:
            # Events can arrive here; ignore for now.
            return

        key = (msg.group, msg.command)
        fut = self._pending.get(key)
        if fut is not None and not fut.done():
            fut.set_result(msg)

    async def send_and_wait(self, group: int, command: int, body: bytes, timeout_s: float = 3.0) -> ProtoMsg:
        data = encode_message(group=group, command=command, body=body, is_reply=False)
        if self._verbose:
            print(f"[BLE-TX] Sending -> Grp: {group}, Cmd: {command}, Body: {_hex(body)}")
            print(f"[BLE-TX-RAW] {_hex(data)}")
        key = (group, command)
        async with self._lock:
            fut = asyncio.get_running_loop().create_future()
            self._pending[key] = fut
            await self._client.write_gatt_char(self._write_uuid, data, response=True)
        try:
            msg = await asyncio.wait_for(fut, timeout=timeout_s)
            return msg
        finally:
            async with self._lock:
                # Only clear if this fut is still the pending one.
                if self._pending.get(key) is fut:
                    self._pending.pop(key, None)


def on_disconnect(_client):
    # bleak calls this on unexpected disconnect
    print("[BLE] Disconnected")


async def scan_uvpro(timeout_s: float) -> List[Tuple[Any, Any]]:
    try:
        from bleak import BleakScanner  # type: ignore
    except Exception:
        raise RuntimeError("Missing dependency: bleak. Install with: pip install bleak")

    found: Dict[str, Tuple[Any, Any]] = {}

    def cb(device, adv_data):
        uuids = [u.lower() for u in (adv_data.service_uuids or [])]
        if RADIO_SERVICE_UUID in uuids:
            found[device.address] = (device, adv_data)

    scanner = BleakScanner(detection_callback=cb)
    await scanner.start()
    try:
        await asyncio.sleep(timeout_s)
    finally:
        await scanner.stop()
    return list(found.values())


async def scan_all(timeout_s: float) -> List[Any]:
    try:
        from bleak import BleakScanner  # type: ignore
    except Exception:
        raise RuntimeError("Missing dependency: bleak. Install with: pip install bleak")

    # On macOS, a discovery scan is often required before connecting by UUID.
    return await BleakScanner.discover(timeout=timeout_s)


@dataclasses.dataclass
class SeenDevice:
    address: str
    name: str
    rssi: Optional[int]
    service_uuids: List[str]
    device: Any


async def scan_index(timeout_s: float, name_contains: Optional[str], min_rssi: Optional[int]) -> List[SeenDevice]:
    try:
        from bleak import BleakScanner  # type: ignore
    except Exception:
        raise RuntimeError("Missing dependency: bleak. Install with: pip install bleak")

    seen: Dict[str, SeenDevice] = {}
    name_contains_l = name_contains.lower() if name_contains else None

    def cb(device, adv_data):
        addr = str(getattr(device, "address", ""))
        if not addr:
            return
        name = getattr(device, "name", None) or "(no name)"
        uuids = [u.lower() for u in (adv_data.service_uuids or [])]
        rssi = getattr(adv_data, "rssi", None)
        if name_contains_l and name.lower().find(name_contains_l) == -1:
            return
        if min_rssi is not None and rssi is not None and rssi < min_rssi:
            return
        seen[addr] = SeenDevice(address=addr, name=name, rssi=rssi, service_uuids=uuids, device=device)

    scanner = BleakScanner(detection_callback=cb)
    await scanner.start()
    try:
        await asyncio.sleep(timeout_s)
    finally:
        await scanner.stop()

    items = list(seen.values())
    items.sort(key=lambda d: (d.rssi if d.rssi is not None else -9999), reverse=True)
    return items


def make_bleak_client(BleakClient: Any, target: Any, args: Any, disconnected_cb: Any = None) -> Any:
    """Construct BleakClient using best-effort kwargs for this bleak version."""

    kwargs: Dict[str, Any] = {}
    # bleak 2.x expects timeout on the constructor, not connect().
    if getattr(args, "connect_timeout", None) is not None:
        kwargs["timeout"] = args.connect_timeout
    if disconnected_cb is not None:
        kwargs["disconnected_callback"] = disconnected_cb
    # Limiting requested services can improve discovery/connection on macOS.
    if not getattr(args, "no_request_services", False):
        kwargs["services"] = [RADIO_SERVICE_UUID]
    if getattr(args, "pair", False):
        kwargs["pair"] = True

    # Try the most featureful constructor first, then degrade.
    for drop_key in (None, "pair", "disconnected_callback", "timeout"):
        try_kwargs = dict(kwargs)
        if drop_key is not None:
            try_kwargs.pop(drop_key, None)
        try:
            return BleakClient(target, **try_kwargs)
        except TypeError:
            continue
    return BleakClient(target)


async def connect_with_retries(client: Any, args: Any, label: str) -> None:
    retries = max(1, int(getattr(args, "connect_retries", 1)))
    backoff_ms = max(0, int(getattr(args, "connect_backoff_ms", 0)))

    last_exc: Optional[BaseException] = None
    for attempt in range(1, retries + 1):
        if getattr(args, "verbose", False):
            extra = "" if retries == 1 else f" (attempt {attempt}/{retries})"
            print(f"[BLE] Connecting to {label}{extra}")
        try:
            backend = getattr(client, "_backend", None)

            # iOS/CoreBluetooth typical flow: connect first, then discover services.
            # bleak CoreBluetooth backend discovers services during connect(); some
            # peripherals disconnect during that phase. Work around by temporarily
            # replacing _get_services during connect.
            orig_get_services = None
            if getattr(args, "ios_connect", False) and backend is not None and hasattr(backend, "_get_services"):
                orig_get_services = getattr(backend, "_get_services")
                try:
                    from bleak.backends.service import BleakGATTServiceCollection  # type: ignore
                except Exception:
                    BleakGATTServiceCollection = None

                async def _no_services(self):
                    if BleakGATTServiceCollection is None:
                        self.services = []
                        return self.services
                    self.services = BleakGATTServiceCollection()
                    return self.services

                backend._get_services = types.MethodType(_no_services, backend)

            # Optional delay before service discovery during connect (when not using ios_connect).
            delay_ms = int(getattr(args, "service_discovery_delay_ms", 0) or 0)
            if delay_ms > 0 and not getattr(args, "ios_connect", False):
                if backend is not None and hasattr(backend, "_get_services") and not hasattr(
                    backend, "_uvpro_delay_patch"
                ):
                    orig = getattr(backend, "_get_services")

                    async def _delayed_get_services(self):
                        await asyncio.sleep(delay_ms / 1000.0)
                        return await orig()

                    backend._get_services = types.MethodType(_delayed_get_services, backend)
                    backend._uvpro_delay_patch = True

            # bleak 1.x uses connect(timeout=...), bleak 2.x ignores it.
            # Also wrap in asyncio timeout so we never hang indefinitely.
            attempt_timeout_s = float(
                getattr(args, "connect_attempt_timeout", None)
                or (getattr(args, "connect_timeout", 10.0) + 10.0)
            )

            async def _do_connect() -> None:
                try:
                    await client.connect(timeout=getattr(args, "connect_timeout", None))
                except TypeError:
                    await client.connect()

            try:
                await asyncio.wait_for(_do_connect(), timeout=attempt_timeout_s)
            finally:
                if orig_get_services is not None and backend is not None:
                    backend._get_services = orig_get_services
            if getattr(client, "is_connected", True):
                return
            raise RuntimeError("connect returned but is_connected is false")
        except Exception as e:
            last_exc = e
            if getattr(args, "verbose", False):
                print(f"[BLE] Connect failed: {type(e).__name__}: {e}")
                print(traceback.format_exc().rstrip())
            try:
                await client.disconnect()
            except Exception:
                pass
            if attempt < retries and backoff_ms > 0:
                await asyncio.sleep(backoff_ms / 1000.0)

    raise RuntimeError(f"Connect failed after {retries} attempt(s): {last_exc}")


async def connect(args) -> Tuple[Optional[UVProBle], Optional[Any]]:
    try:
        from bleak import BleakClient  # type: ignore
    except Exception:
        raise RuntimeError("Missing dependency: bleak. Install with: pip install bleak")

    device_address: Optional[str] = args.uuid

    if args.list:
        items = await scan_index(
            timeout_s=args.scan_timeout,
            name_contains=args.name_contains,
            min_rssi=args.min_rssi,
        )
        if not items:
            print("No BLE devices discovered.")
            return None, None
        print(f"Discovered {len(items)} BLE device(s):")
        for i, d in enumerate(items):
            svc = "" if not d.service_uuids else f" svcs={len(d.service_uuids)}"
            rssi = "" if d.rssi is None else f" rssi={d.rssi}"
            print(f"  [{i}] {d.name}  addr={d.address}{rssi}{svc}")
        return None, None

    if args.probe:
        items = await scan_index(
            timeout_s=args.scan_timeout,
            name_contains=args.name_contains,
            min_rssi=args.min_rssi,
        )
        if not items:
            print("No BLE devices discovered.")
            return None, None

        limit = min(args.probe_limit, len(items))
        print(f"Probing top {limit} device(s) for UV-PRO GATT service...")
        for i in range(limit):
            d = items[i]
            rssi = "" if d.rssi is None else f" rssi={d.rssi}"
            print(f"  [{i}] {d.name} addr={d.address}{rssi}")
            c = None
            try:
                c = make_bleak_client(BleakClient, d.device, args, disconnected_cb=on_disconnect)
                await connect_with_retries(c, args, label=f"{d.address} ({d.name})")
                svcs = await discover_services(c)
                has_service = False
                has_write = False
                has_indicate = False
                for s in svcs:
                    if str(s.uuid).lower() == RADIO_SERVICE_UUID:
                        has_service = True
                    for ch in s.characteristics:
                        cu = str(ch.uuid).lower()
                        if cu == RADIO_WRITE_UUID:
                            has_write = True
                        elif cu == RADIO_INDICATE_UUID:
                            has_indicate = True
                await c.disconnect()
                if has_service and has_write and has_indicate:
                    print(f"FOUND UV-PRO: addr={d.address} name={d.name}")
                    print("Use it with: --uuid <addr>")
                    return None, None
            except Exception as e:
                try:
                    if c is not None:
                        await c.disconnect()
                except Exception:
                    pass
                if args.verbose:
                    print(f"    probe failed: {e}")

        print("No UV-PRO-like device found in probe set.")
        return None, None

    if device_address:
        # Prefer direct connect to the explicit address/UUID.
        try:
            if args.verbose:
                print(f"[BLE] Connecting (direct) to {device_address}")
            client = make_bleak_client(BleakClient, device_address, args, disconnected_cb=on_disconnect)
            await connect_with_retries(client, args, label=f"{device_address} (direct)")
        except Exception as e:
            # On macOS, direct connect by UUID often fails unless the device was discovered
            # during the same session. Fall back to a scan and connect via the BleakDevice.
            if args.verbose:
                print(f"[BLE] Direct connect failed, falling back to scan: {type(e).__name__}: {e}")

            items = await scan_index(
                timeout_s=args.scan_timeout,
                name_contains=args.name_contains,
                min_rssi=args.min_rssi,
            )
            match = None
            for d in items:
                if d.address.lower() == device_address.lower():
                    match = d
                    break
            if match is None:
                if args.force_scan:
                    raise RuntimeError(f"Device {device_address} not discovered during scan.")
                raise RuntimeError(
                    f"Direct connect failed for {device_address}: {e}. "
                    "Device not rediscovered during scan. Run --list to find the macOS address, "
                    "or rerun with --force-scan and a longer --scan-timeout."
                )
            if args.verbose:
                print(f"[BLE] Connecting (scanned match) to {match.address} name={match.name}")
            client = make_bleak_client(BleakClient, match.device, args, disconnected_cb=on_disconnect)
            await connect_with_retries(client, args, label=f"{match.address} ({match.name})")

    elif args.pick is not None:
        # If filters are provided, pick from the filtered device list.
        if args.name_contains or args.min_rssi is not None:
            items = await scan_index(
                timeout_s=args.scan_timeout,
                name_contains=args.name_contains,
                min_rssi=args.min_rssi,
            )
            if not items:
                raise RuntimeError("No BLE devices discovered.")
            if args.pick < 0 or args.pick >= len(items):
                raise RuntimeError("--pick out of range")
            if args.verbose:
                d = items[args.pick]
                print(f"[BLE] Connecting (pick) to {d.address} name={d.name}")
            client = make_bleak_client(BleakClient, items[args.pick].device, args, disconnected_cb=on_disconnect)
            await connect_with_retries(client, args, label=f"{items[args.pick].address} ({items[args.pick].name})")
        else:
            # Otherwise, prefer picking among UV-PRO advertisers when present.
            found = await scan_uvpro(timeout_s=args.scan_timeout)
            if not found:
                raise RuntimeError("No UV-PRO advertisers found. Use --scan or --list to debug.")
            if args.pick < 0 or args.pick >= len(found):
                raise RuntimeError(f"--pick out of range for UV-PRO list (0..{len(found)-1})")
            device, _adv = found[args.pick]
            if args.verbose:
                name = getattr(device, "name", None) or "(no name)"
                print(f"[BLE] Connecting (pick uvpro) to {device.address} name={name}")
            client = make_bleak_client(BleakClient, device, args, disconnected_cb=on_disconnect)
            await connect_with_retries(client, args, label=f"{device.address} ({getattr(device,'name',None) or '(no name)'})")

    else:
        found = await scan_uvpro(timeout_s=args.scan_timeout)
        if args.scan:
            if not found:
                print("No UV-PRO advertisers found.")
                return None, None
            print(f"Found {len(found)} UV-PRO advertiser(s):")
            for i, (dev, adv) in enumerate(found):
                name = getattr(dev, "name", None) or "(no name)"
                rssi = getattr(adv, "rssi", None)
                print(f"  [{i}] {name}  addr={dev.address}  rssi={rssi}")
            return None, None

        if not found:
            raise RuntimeError("No UV-PRO advertisers found. Use --scan to debug.")

        if len(found) == 1:
            device, _adv = found[0]
            device_address = device.address
        else:
            print(f"Found {len(found)} UV-PRO advertiser(s):")
            for i, (dev, adv) in enumerate(found):
                name = getattr(dev, "name", None) or "(no name)"
                rssi = getattr(adv, "rssi", None)
                print(f"  [{i}] {name}  addr={dev.address}  rssi={rssi}")
            if args.pick is None:
                raise RuntimeError("Multiple devices found. Re-run with --pick N or --uuid <addr>.")
            idx = args.pick
            if idx < 0 or idx >= len(found):
                raise RuntimeError("--pick out of range")
            device, _adv = found[idx]
            device_address = device.address

        client = BleakClient(device_address)
        client = make_bleak_client(BleakClient, device_address, args, disconnected_cb=on_disconnect)
        await connect_with_retries(client, args, label=f"{device_address} (auto)")

    # Ensure services are discovered
    if args.verbose:
        print("[BLE] Discovering services")

    # If we used ios_connect, we intentionally skipped service discovery during
    # connect; do it now after a settle delay.
    settle_ms = int(getattr(args, "post_connect_settle_ms", 0) or 0)
    if settle_ms > 0:
        await asyncio.sleep(settle_ms / 1000.0)

    services = None
    svc_tries = max(1, int(getattr(args, "service_discovery_retries", 1)))
    for i in range(svc_tries):
        try:
            services = await discover_services_force(client) if getattr(args, "ios_connect", False) else await discover_services(client)
            break
        except Exception as e:
            if args.verbose:
                print(f"[BLE] Service discovery failed ({i+1}/{svc_tries}): {type(e).__name__}: {e}")
                print(traceback.format_exc().rstrip())
            if i + 1 == svc_tries:
                raise
            await asyncio.sleep(0.6)

    assert services is not None

    write_uuid = None
    indicate_uuid = None
    for s in services:
        for c in s.characteristics:
            cu = str(c.uuid).lower()
            if cu == RADIO_WRITE_UUID:
                write_uuid = cu
            elif cu == RADIO_INDICATE_UUID:
                indicate_uuid = cu

    if not write_uuid or not indicate_uuid:
        await client.disconnect()
        raise RuntimeError(
            f"Missing required characteristics. write={write_uuid} indicate={indicate_uuid}"
        )

    uv = UVProBle(client, write_uuid=write_uuid, indicate_uuid=indicate_uuid, verbose=args.verbose)
    if args.verbose:
        print(f"[BLE] Subscribing to indications on {indicate_uuid}")
    await client.start_notify(indicate_uuid, uv._on_notify)
    if args.verbose:
        print("[BLE] Notify subscription active")
    return uv, client


async def get_region_names(uv: UVProBle, max_regions: int) -> List[str]:
    names: List[str] = []
    for i in range(max_regions):
        msg = await uv.send_and_wait(group=2, command=73, body=encode_read_region_name(i))
        status, region_echo, name, raw = decode_region_name_reply(msg.body)
        if status != 0:
            break
        if region_echo != i:
            print(f"[WARN] readRegionName echo mismatch: requested={i} reply={region_echo}")
        names.append(name)
    return names


def diff_indices(before: List[str], after: List[str]) -> List[int]:
    out: List[int] = []
    for i, (a, b) in enumerate(zip(before, after)):
        if a != b:
            out.append(i)
    return out


async def try_rename_id(uv: UVProBle, region_id: int, name: str) -> None:
    msg = await uv.send_and_wait(group=2, command=59, body=encode_write_region_name_id(region_id, name))
    st = decode_reply_status(msg.body)
    if st != 0:
        raise RuntimeError(f"writeRegionName(id+name) failed status={st}")


async def try_rename_current(uv: UVProBle, region_id: int, name: str, settle_ms: int = 250) -> None:
    msg = await uv.send_and_wait(group=2, command=60, body=encode_set_region(region_id))
    st = decode_reply_status(msg.body)
    if st != 0:
        raise RuntimeError(f"setRegion failed status={st}")
    await asyncio.sleep(settle_ms / 1000.0)

    msg = await uv.send_and_wait(group=2, command=59, body=encode_write_region_name_current(name))
    st = decode_reply_status(msg.body)
    if st != 0:
        raise RuntimeError(f"writeRegionName(name-only) failed status={st}")


async def main_async() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--uuid", help="Peripheral address/UUID (macOS: UUID string)")
    p.add_argument("--scan", action="store_true", help="Scan and list UV-PRO advertisers")
    p.add_argument("--list", action="store_true", help="Scan and list BLE devices (no auto connect)")
    p.add_argument("--probe", action="store_true", help="Scan then probe devices to find UV-PRO GATT")
    p.add_argument("--probe-limit", type=int, default=12, help="How many devices to probe (RSSI-sorted)")
    p.add_argument("--pick", type=int, help="Pick device index from scan when multiple found")
    p.add_argument("--scan-timeout", type=float, default=5.0)
    p.add_argument("--connect-timeout", type=float, default=8.0)
    p.add_argument(
        "--connect-attempt-timeout",
        type=float,
        default=30.0,
        help="Async timeout for a single connect attempt (prevents hangs)",
    )
    p.add_argument("--connect-retries", type=int, default=5)
    p.add_argument("--connect-backoff-ms", type=int, default=600)
    p.add_argument("--pair", action="store_true", help="Attempt to pair on connect (if supported)")
    p.add_argument(
        "--no-request-services",
        action="store_true",
        help="Do not limit CoreBluetooth service discovery (debug option)",
    )
    p.add_argument(
        "--service-discovery-delay-ms",
        type=int,
        default=800,
        help="Delay before service discovery during connect (macOS/CoreBluetooth)",
    )
    p.add_argument(
        "--ios-connect",
        action="store_true",
        default=True,
        help="Use iOS-like flow: connect first, discover services after",
    )
    p.add_argument(
        "--no-ios-connect",
        dest="ios_connect",
        action="store_false",
        help="Disable iOS-like flow (use bleak default connect behavior)",
    )
    p.add_argument(
        "--post-connect-settle-ms",
        type=int,
        default=1500,
        help="Wait after connect before service discovery (ios-connect)",
    )
    p.add_argument(
        "--service-discovery-retries",
        type=int,
        default=3,
        help="Retries for service discovery after connect",
    )
    p.add_argument("--verbose", action="store_true", help="Print raw TX/RX frames")
    p.add_argument("--force-scan", action="store_true", help="If direct connect fails, scan and retry")
    p.add_argument("--name-contains", help="Only show/match devices with name containing substring")
    p.add_argument("--min-rssi", type=int, help="Only show/match devices with RSSI >= value")

    g = p.add_mutually_exclusive_group(required=False)
    g.add_argument("--read", action="store_true", help="Read region names")
    g.add_argument("--rename", nargs=2, metavar=("INDEX", "NAME"), help="Rename one region")
    g.add_argument("--matrix", metavar="INDEX", help="Run theory matrix experiment on region")

    p.add_argument("--max-regions", type=int, default=16)
    p.add_argument("--no-restore", action="store_true", help="Do not restore original names")
    args = p.parse_args()

    uv, client = await connect(args)
    if uv is None or client is None:
        return 0
    try:
        # Probe region count via DevInfo if possible
        region_cap = args.max_regions
        try:
            dev = await uv.send_and_wait(group=2, command=4, body=b"\x03")
            rc = decode_dev_info_region_count(dev.body)
            if rc > 0:
                region_cap = min(region_cap, rc)
                print(f"[INFO] DevInfo regionCount={rc}")
        except Exception as e:
            print(f"[WARN] DevInfo decode failed; using --max-regions={region_cap} ({e})")

        before = await get_region_names(uv, max_regions=region_cap)
        print("[REGIONS] Before:")
        for i, n in enumerate(before):
            shown = n if n else f"(empty)"
            print(f"  {i}: {shown}")

        if args.read or (not args.rename and not args.matrix):
            return 0

        original = before[:]

        if args.rename:
            idx = int(args.rename[0])
            name = args.rename[1]
            if idx < 0 or idx >= len(before):
                raise RuntimeError(f"index out of range (0..{len(before)-1})")

            # Prefer current-region path (setRegion + name-only), then fallback.
            try:
                print(f"[RENAME] current-region path: setRegion({idx}) + write(name-only='{name}')")
                await try_rename_current(uv, idx, name)
            except Exception as e:
                print(f"[RENAME] current-region path failed: {e}")
                print(f"[RENAME] fallback path: write(id+name, id={idx}, name='{name}')")
                await try_rename_id(uv, idx, name)

            after = await get_region_names(uv, max_regions=len(before))
            changed = diff_indices(before, after)
            print(f"[REGIONS] Changed indices: {changed}")
            print("[REGIONS] After:")
            for i, n in enumerate(after):
                shown = n if n else f"(empty)"
                print(f"  {i}: {shown}")

            if not args.no_restore:
                print("[RESTORE] Restoring original names...")
                for i, old in enumerate(original):
                    try:
                        await try_rename_current(uv, i, old)
                    except Exception:
                        await try_rename_id(uv, i, old)
                print("[RESTORE] Done")
            return 0

        if args.matrix is not None:
            idx = int(args.matrix)
            if idx < 0 or idx >= len(before):
                raise RuntimeError(f"index out of range (0..{len(before)-1})")

            # Keep names <= 10 bytes.
            name_a = f"T{idx}A"
            name_b = f"T{idx}B"
            name_c = f"T{idx}C"

            print(f"[MATRIX] Target region {idx}")
            print(f"[MATRIX] A: write(id+name) without setRegion -> '{name_a}'")
            await try_rename_id(uv, idx, name_a)
            after_a = await get_region_names(uv, max_regions=len(before))
            print(f"[MATRIX] A changed: {diff_indices(before, after_a)}")

            print(f"[MATRIX] B: setRegion(idx) + write(name-only) -> '{name_b}'")
            await try_rename_current(uv, idx, name_b)
            after_b = await get_region_names(uv, max_regions=len(before))
            print(f"[MATRIX] B changed: {diff_indices(after_a, after_b)}")

            print(f"[MATRIX] C: setRegion(idx) + write(id+name) -> '{name_c}'")
            msg = await uv.send_and_wait(group=2, command=60, body=encode_set_region(idx))
            st = decode_reply_status(msg.body)
            if st != 0:
                raise RuntimeError(f"setRegion failed status={st}")
            await asyncio.sleep(0.25)
            await try_rename_id(uv, idx, name_c)
            after_c = await get_region_names(uv, max_regions=len(before))
            print(f"[MATRIX] C changed: {diff_indices(after_b, after_c)}")

            print("[REGIONS] Final:")
            for i, n in enumerate(after_c):
                shown = n if n else f"(empty)"
                print(f"  {i}: {shown}")

            if not args.no_restore:
                print("[RESTORE] Restoring original names...")
                for i, old in enumerate(original):
                    try:
                        await try_rename_current(uv, i, old)
                    except Exception:
                        await try_rename_id(uv, i, old)
                print("[RESTORE] Done")
            return 0

        return 0
    finally:
        try:
            await client.stop_notify(uv.indicate_uuid)
        except Exception:
            pass
        try:
            await client.disconnect()
        except Exception:
            pass


def main() -> int:
    try:
        return asyncio.run(main_async())
    except KeyboardInterrupt:
        return 130
    except Exception as e:
        print(f"ERROR: {type(e).__name__}: {e}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
