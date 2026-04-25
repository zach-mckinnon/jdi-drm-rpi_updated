#!/usr/bin/python3
import argparse
import json
import sys
from pathlib import Path

SYSFS_ROOT = Path("/sys/firmware/beepy")
BATTERY_PERCENT_PATH = SYSFS_ROOT / "battery_percent"
BATTERY_VOLTS_PATH = SYSFS_ROOT / "battery_volts"
BATTERY_RAW_PATH = SYSFS_ROOT / "battery_raw"


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="ascii").strip()
    except FileNotFoundError:
        return None


def read_battery() -> dict[str, str | None]:
    return {
        "percent": read_text(BATTERY_PERCENT_PATH),
        "volts": read_text(BATTERY_VOLTS_PATH),
        "raw": read_text(BATTERY_RAW_PATH),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Show Beepy / ColorBerry battery information."
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print all available battery values as JSON",
    )
    parser.add_argument(
        "--percent",
        action="store_true",
        help="print only the battery percentage",
    )
    parser.add_argument(
        "--volts",
        action="store_true",
        help="print only the estimated battery voltage",
    )
    parser.add_argument(
        "--raw",
        action="store_true",
        help="print only the raw battery value reported by firmware",
    )
    args = parser.parse_args()

    data = read_battery()
    if not any(data.values()):
        print(
            "Battery sysfs entries were not found under /sys/firmware/beepy. "
            "Make sure beepy-kbd is loaded.",
            file=sys.stderr,
        )
        return 1

    if args.json:
        print(json.dumps(data))
        return 0

    if args.percent:
        if data["percent"] is None:
            return 1
        print(data["percent"])
        return 0

    if args.volts:
        if data["volts"] is None:
            return 1
        print(data["volts"])
        return 0

    if args.raw:
        if data["raw"] is None:
            return 1
        print(data["raw"])
        return 0

    parts = []
    if data["percent"] is not None:
        parts.append(f"{data['percent']}%")
    if data["volts"] is not None:
        parts.append(f"{data['volts']}V")
    if data["raw"] is not None:
        parts.append(f"raw={data['raw']}")

    print(" ".join(parts))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
