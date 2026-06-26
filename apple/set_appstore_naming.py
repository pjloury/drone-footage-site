#!/usr/bin/env python3
"""
Human-readable product names + App Store metadata for the macOS app and
screen saver. Product files become 'Aerial Landscapes.app' /
'Aerial Landscapes.saver' (never the concatenated 'AerialLandscapes' form);
display name stays the short 'Aerial Landscapes'.
"""
import plistlib, subprocess, shutil, os

PBXPROJ = os.path.join(os.path.dirname(__file__),
                       "AerialLandscapes.xcodeproj", "project.pbxproj")
XML_TMP = "/tmp/project_naming.xml"
COPYRIGHT = "Copyright © 2026 PJ Loury. All rights reserved."

# App configs (AerialLandscapesMac) and saver configs (AerialLandscapesSaver).
APP_CFGS   = ["AA0001072D238122004DA734", "AA0001082D238122004DA734"]
SAVER_CFGS = ["CC0001060000000000000001", "CC0001070000000000000001"]


def convert(src, dst, fmt):
    subprocess.run(["plutil", "-convert", fmt, src, "-o", dst], check=True)


def main():
    shutil.copy(PBXPROJ, PBXPROJ + ".bak")
    convert(PBXPROJ, XML_TMP, "xml1")
    with open(XML_TMP, "rb") as f:
        data = plistlib.load(f)
    objs = data["objects"]

    for cfg in APP_CFGS:
        bs = objs[cfg]["buildSettings"]
        bs["PRODUCT_NAME"] = "Aerial Landscapes"
        bs["INFOPLIST_KEY_CFBundleDisplayName"] = "Aerial Landscapes"
        bs["INFOPLIST_KEY_NSHumanReadableCopyright"] = COPYRIGHT

    # Distinct product/module name avoids a swiftmodule collision with the app,
    # while staying human-readable (never the concatenated form). The picker-
    # facing display name stays the short 'Aerial Landscapes'.
    for cfg in SAVER_CFGS:
        bs = objs[cfg]["buildSettings"]
        bs["PRODUCT_NAME"] = "Aerial Landscapes Screen Saver"
        bs["INFOPLIST_KEY_CFBundleDisplayName"] = "Aerial Landscapes"
        bs["INFOPLIST_KEY_NSHumanReadableCopyright"] = COPYRIGHT

    with open(PBXPROJ, "wb") as f:
        plistlib.dump(data, f)
    print("✅  app='Aerial Landscapes', saver='Aerial Landscapes Screen Saver' + copyright")


if __name__ == "__main__":
    main()
