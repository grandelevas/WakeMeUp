#!/usr/bin/env python3
"""Print the UDID of the newest available iPhone simulator."""

from __future__ import annotations

import json
import subprocess
import sys

PREFERRED = ["iPhone 17", "iPhone 17 Pro", "iPhone Air", "iPhone 16", "iPhone 16 Pro"]


def main() -> None:
    raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
    data = json.loads(raw)
    candidates: list[tuple[str, int, dict]] = []
    for runtime, devices in data.get("devices", {}).items():
        if "iOS" not in runtime:
            continue
        for device in devices:
            if not device.get("isAvailable"):
                continue
            name = device.get("name", "")
            if name in PREFERRED:
                candidates.append((runtime, PREFERRED.index(name), device))
    if not candidates:
        print("No preferred iPhone simulator is installed.", file=sys.stderr)
        print(raw.decode()[:5000], file=sys.stderr)
        sys.exit(1)
    # Newest runtime last. Within a runtime, the earliest preferred name last.
    candidates.sort(key=lambda item: (item[0], -item[1]))
    runtime, _, device = candidates[-1]
    print(f"{device['name']} on {runtime}", file=sys.stderr)
    print(device["udid"])


if __name__ == "__main__":
    main()
