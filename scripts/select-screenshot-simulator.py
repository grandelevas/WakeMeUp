#!/usr/bin/env python3
"""Print the UDID of an iPhone Pro Max simulator for 6.9-inch App Store screenshots."""

from __future__ import annotations

import json
import subprocess
import sys

# iPhone 16 Pro Max is 1320x2868. Prefer it, then any newer Pro Max.
PREFERRED = [
    "iPhone 16 Pro Max",
    "iPhone 17 Pro Max",
    "iPhone 18 Pro Max",
]


def main() -> None:
    raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
    data = json.loads(raw)
    found: list[tuple[str, int, dict]] = []
    for runtime, devices in data.get("devices", {}).items():
        if "iOS" not in runtime:
            continue
        for device in devices:
            if not device.get("isAvailable"):
                continue
            name = device.get("name", "")
            if name in PREFERRED:
                found.append((runtime, PREFERRED.index(name), device))
    if not found:
        print("No iPhone Pro Max simulator is installed.", file=sys.stderr)
        names = []
        for runtime, devices in data.get("devices", {}).items():
            for device in devices:
                if device.get("isAvailable") and "iPhone" in device.get("name", ""):
                    names.append(f"{device.get('name')} ({runtime})")
        print("\n".join(names[:40]), file=sys.stderr)
        sys.exit(1)
    best_index = min(item[1] for item in found)
    same = [item for item in found if item[1] == best_index]
    same.sort(key=lambda item: item[0])
    runtime, _, device = same[-1]
    print(f"{device['name']} on {runtime}", file=sys.stderr)
    print(device["udid"])


if __name__ == "__main__":
    main()
