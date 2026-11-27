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

    for label, plist in (("app", app), ("widget", widget)):
        for key in ("CFBundleDisplayName", "CFBundleName"):
            if plist.get(key) != "Wakito":
                print(f"{label} {key} must be Wakito, got {plist.get(key)!r}", file=sys.stderr)
                return 1
    for key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription"):
        value = app.get(key)
        if not isinstance(value, str) or not value.strip():
            print(f"Info.plist must explain {key}", file=sys.stderr)
            return 1
        for language in ("en", "pl"):
            text = (ROOT / "WakeMeUp" / "Resources" / f"{language}.lproj" / "InfoPlist.strings").read_text()
            if f'"{key}"' not in text:
                print(f"{language} InfoPlist.strings must localize {key}", file=sys.stderr)
                return 1

    if app.get("CKSharingSupported") is not True:
        print("CKSharingSupported must stay true so iCloud share links can open the app", file=sys.stderr)
        return 1
    if "PRODUCT_BUNDLE_IDENTIFIER: com.grandelevas.wakemeup" not in project:
        print("bundle id must stay com.grandelevas.wakemeup", file=sys.stderr)
        return 1

    print("app Info.plist keeps iPhone portrait, all four iPad orientations, and the Wakito name")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
