#!/usr/bin/env python3
"""
Transmit periodic CAN frames to match LOCAL_ID in can_top.v.

Default behavior:
- Reads LOCAL_ID from can_top.v (e.g. 11'h456)
- Sends standard 11-bit CAN data frames periodically
- Intended for USB<->CAN adapters such as AZSMZ (typically slcan)

Examples:
  python3 can_tx_periodic.py --channel /dev/ttyUSB0 --can-bitrate 500000
  python3 can_tx_periodic.py --interface socketcan --channel can0
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
import time


try:
    import can
except ImportError:
    print("ERROR: python-can is required. Install with: pip install python-can")
    sys.exit(1)


def parse_verilog_number(token: str) -> int:
    """Parse Verilog numeric literal, e.g. 11'h456, 29'd123, 8'b10101010."""
    text = token.strip().lower().replace("_", "")
    m = re.fullmatch(r"(?:(\d+)')?([bdho])([0-9a-fx]+)", text)
    if m:
        base_code = m.group(2)
        digits = m.group(3).replace("x", "0")
        base = {"b": 2, "d": 10, "h": 16, "o": 8}[base_code]
        return int(digits, base)

    # plain decimal fallback
    if re.fullmatch(r"\d+", text):
        return int(text, 10)

    raise ValueError(f"Unsupported Verilog number format: {token}")


def extract_local_id(can_top_path: pathlib.Path) -> int:
    """Extract LOCAL_ID parameter default value from can_top.v."""
    src = can_top_path.read_text(encoding="utf-8", errors="ignore")
    m = re.search(r"parameter\s*\[\s*10\s*:\s*0\s*\]\s*LOCAL_ID\s*=\s*([^,\n\r]+)", src)
    if not m:
        raise RuntimeError("Could not find LOCAL_ID in can_top.v")
    return parse_verilog_number(m.group(1).strip())


def build_payload(counter: int) -> bytes:
    c = counter & 0xFFFFFFFF
    return bytes([
        (c >> 24) & 0xFF,
        (c >> 16) & 0xFF,
        (c >> 8) & 0xFF,
        c & 0xFF,
        0xCA,
        0xFE,
        0xBE,
        0xEF,
    ])


def open_bus(args: argparse.Namespace) -> can.BusABC:
    kwargs = {
        "interface": args.interface,
        "channel": args.channel,
        "bitrate": args.can_bitrate,
    }

    # slcan adapters often need serial baud too
    if args.interface == "slcan" and args.serial_baud is not None:
        kwargs["tty_baudrate"] = args.serial_baud

    return can.Bus(**kwargs)


def main() -> int:
    parser = argparse.ArgumentParser(description="Periodic CAN TX using LOCAL_ID from can_top.v")
    parser.add_argument("--can-top", default="can_top.v", help="Path to can_top.v")
    parser.add_argument("--interface", default="slcan", help="python-can interface (slcan/socketcan/pcan/...)" )
    parser.add_argument("--channel", default="/dev/ttyACM0", help="CAN channel/device (e.g. /dev/ttyUSB0 or can0)")
    parser.add_argument("--can-bitrate", type=int, default=500000, help="CAN bitrate in bps")
    parser.add_argument("--serial-baud", type=int, default=115200, help="UART baud to USB-CAN dongle (slcan)")
    parser.add_argument("--period", type=float, default=0.1, help="Frame period in seconds")
    parser.add_argument("--dlc", type=int, default=8, choices=range(0, 9), help="Data length code")
    parser.add_argument("--id", dest="forced_id", default=None, help="Override ID (e.g. 0x456)")
    args = parser.parse_args()

    can_top_path = pathlib.Path(args.can_top)

    if args.forced_id is None:
        can_id = extract_local_id(can_top_path)
    else:
        can_id = int(args.forced_id, 0)

    if not (0 <= can_id <= 0x7FF):
        print(f"ERROR: This script sends standard frames. ID out of range: 0x{can_id:X}")
        return 2

    print(f"Using CAN ID: 0x{can_id:03X} (from {'--id' if args.forced_id else can_top_path})")
    print(f"Interface={args.interface}, channel={args.channel}, bitrate={args.can_bitrate}, period={args.period}s")

    try:
        bus = open_bus(args)
    except Exception as exc:
        print(f"ERROR: Failed to open CAN interface: {exc}")
        return 3

    counter = 0
    next_t = time.monotonic()

    print("Transmitting... Press Ctrl+C to stop.")
    try:
        while True:
            payload = build_payload(counter)[: args.dlc]
            msg = can.Message(
                arbitration_id=can_id,
                is_extended_id=False,
                is_remote_frame=False,
                data=payload,
            )
            bus.send(msg)
            print(f"TX id=0x{can_id:03X} dlc={len(payload)} data={payload.hex(' ')}")
            counter += 1

            next_t += args.period
            sleep_t = next_t - time.monotonic()
            if sleep_t > 0:
                time.sleep(sleep_t)
            else:
                # if delayed, re-sync to avoid drift explosion
                next_t = time.monotonic()

    except KeyboardInterrupt:
        print("Stopped by user.")
    except Exception as exc:
        print(f"ERROR during TX: {exc}")
        return 4
    finally:
        try:
            bus.shutdown()
        except Exception:
            pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
