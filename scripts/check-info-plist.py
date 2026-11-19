#!/usr/bin/env python3
"""Check the app Info.plist that Xcode copies into the bundle.

GENERATE_INFOPLIST_FILE is NO, so WakeMeUp/Info.plist is that file. Ubuntu
cannot run xcodebuild; the orientation keys are literals, not build settings.
"""

import plistlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IPAD = "UISupportedInterfaceOrientations~ipad"
IPHONE = "UISupportedInterfaceOrientations"
ALL_FOUR = [
    "UIInterfaceOrientationPortrait",
    "UIInterfaceOrientationPortraitUpsideDown",
    "UIInterfaceOrientationLandscapeLeft",
    "UIInterfaceOrientationLandscapeRight",
]


def load(path: Path) -> dict:
    with path.open("rb") as handle:
        return plistlib.load(handle)


def main() -> int:
    project = (ROOT / "project.yml").read_text()
    if "INFOPLIST_FILE: WakeMeUp/Info.plist" not in project:
        print("project.yml must point the app target at WakeMeUp/Info.plist", file=sys.stderr)
        return 1
    if "GENERATE_INFOPLIST_FILE: NO" not in project:
        print("project.yml must keep the checked-in Info.plist", file=sys.stderr)
        return 1

    app = load(ROOT / "WakeMeUp" / "Info.plist")
    iphone = app.get(IPHONE)
    ipad = app.get(IPAD)
    if iphone != ["UIInterfaceOrientationPortrait"]:
        print(f"iPhone orientations must stay portrait-only, got {iphone}", file=sys.stderr)
        return 1
    if ipad != ALL_FOUR:
        print(f"iPad orientations must be all four, got {ipad}", file=sys.stderr)
        return 1

    widget = load(ROOT / "WakeMeUpWidget" / "Info.plist")
    for key in (IPHONE, IPAD, "UISupportedInterfaceOrientations~iphone"):
        if key in widget:
            print(f"widget extension must not declare {key}", file=sys.stderr)
            return 1

    print("app Info.plist keeps iPhone portrait and all four iPad orientations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
