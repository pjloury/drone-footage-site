#!/usr/bin/env python3
"""
Set up the 'Both' distribution model:

  * AerialLandscapesMac  → Developer ID (notarized) FULL build: non-sandboxed
    (so global hotkeys + screen-saver install work), hardened runtime on.
  * AerialLandscapesMacMAS → Mac App Store build: sandboxed, MAS compile flag
    (drops hotkeys + saver install), no embedded screen saver, builds into a
    separate dir so it never collides with the Developer ID product.

Run AFTER add_saver_target.py / add_saver_embed.py / set_appstore_naming.py.
"""
import plistlib, subprocess, shutil, os, sys

PBXPROJ = os.path.join(os.path.dirname(__file__),
                       "AerialLandscapes.xcodeproj", "project.pbxproj")
XML_TMP = "/tmp/project_mas.xml"
TEAM    = "D2GRT69L42"

APP_DEBUG  = "AA0001072D238122004DA734"
APP_RELEASE = "AA0001082D238122004DA734"
MAC_GROUP    = "AA0001022D238122004DA734"   # MacWallpaper synced folder
ENGINE_GROUP = "CC0001000000000000000001"   # MacEngine synced folder

U = {
    "app_ref":     "DD0001000000000000000001",
    "src_phase":   "DD0001010000000000000001",
    "fw_phase":    "DD0001020000000000000001",
    "res_phase":   "DD0001030000000000000001",
    "debug_cfg":   "DD0001040000000000000001",
    "release_cfg": "DD0001050000000000000001",
    "cfg_list":    "DD0001060000000000000001",
    "target":      "DD0001070000000000000001",
}


def convert(src, dst, fmt):
    subprocess.run(["plutil", "-convert", fmt, src, "-o", dst], check=True)


def load():
    convert(PBXPROJ, XML_TMP, "xml1")
    with open(XML_TMP, "rb") as f:
        return plistlib.load(f)


def save(data):
    with open(PBXPROJ, "wb") as f:
        plistlib.dump(data, f)


def mas_settings(extra=None):
    base = {
        "SDKROOT": "macosx",
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "SWIFT_VERSION": "5.0",
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": TEAM,
        "PRODUCT_NAME": "Aerial Landscapes",
        "PRODUCT_MODULE_NAME": "AerialLandscapesMAS",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.pjloury.aerial-landscapes",
        "MARKETING_VERSION": "1.0",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.entertainment",
        "INFOPLIST_KEY_LSUIElement": "YES",
        "INFOPLIST_KEY_NSPrincipalClass": "NSApplication",
        "INFOPLIST_KEY_CFBundleDisplayName": "Aerial Landscapes",
        "INFOPLIST_KEY_NSHumanReadableCopyright": "Copyright © 2026 PJ Loury. All rights reserved.",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ENABLE_APP_SANDBOX": "YES",
        "CODE_SIGN_ENTITLEMENTS": "MacWallpaper/Resources/MacWallpaper-MAS.entitlements",
        # Build entirely under build-mas/ so the App Store product never
        # collides with the Developer ID product (both are 'Aerial Landscapes').
        "SYMROOT": "$(PROJECT_DIR)/build-mas",
        "OBJROOT": "$(PROJECT_DIR)/build-mas",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
    }
    if extra:
        base.update(extra)
    return base


def patch(data):
    objs = data["objects"]
    if U["target"] in objs:
        print("MAS target already present — nothing to do.")
        sys.exit(0)

    # ── (a) Make the existing app target Developer-ID-ready ────
    for cfg in (APP_DEBUG, APP_RELEASE):
        bs = objs[cfg]["buildSettings"]
        bs["ENABLE_APP_SANDBOX"] = "NO"
        bs["ENABLE_HARDENED_RUNTIME"] = "YES"

    # ── (b) Add the MAS target ────────────────────────────────
    objs[U["app_ref"]] = {
        "isa": "PBXFileReference",
        "explicitFileType": "wrapper.application",
        "includeInIndex": "0",
        "path": "Aerial Landscapes.app",
        "sourceTree": "BUILT_PRODUCTS_DIR",
    }
    for phase, isa in ((U["src_phase"], "PBXSourcesBuildPhase"),
                       (U["fw_phase"], "PBXFrameworksBuildPhase"),
                       (U["res_phase"], "PBXResourcesBuildPhase")):
        objs[phase] = {"isa": isa, "buildActionMask": "2147483647",
                       "files": [], "runOnlyForDeploymentPostprocessing": "0"}

    objs[U["debug_cfg"]] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": mas_settings({
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) DEBUG MAS",
        }),
        "name": "Debug",
    }
    objs[U["release_cfg"]] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": mas_settings({
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) MAS",
        }),
        "name": "Release",
    }
    objs[U["cfg_list"]] = {
        "isa": "XCConfigurationList",
        "buildConfigurations": [U["debug_cfg"], U["release_cfg"]],
        "defaultConfigurationIsVisible": "0",
        "defaultConfigurationName": "Release",
    }
    objs[U["target"]] = {
        "isa": "PBXNativeTarget",
        "buildConfigurationList": U["cfg_list"],
        "buildPhases": [U["src_phase"], U["fw_phase"], U["res_phase"]],
        "buildRules": [],
        "dependencies": [],
        "fileSystemSynchronizedGroups": [MAC_GROUP, ENGINE_GROUP],
        "name": "AerialLandscapesMacMAS",
        "productName": "AerialLandscapesMacMAS",
        "productReference": U["app_ref"],
        "productType": "com.apple.product-type.application",
    }

    proj_uid = data["rootObject"]
    proj = objs[proj_uid]
    proj["targets"].append(U["target"])
    proj.setdefault("attributes", {}).setdefault("TargetAttributes", {})[U["target"]] = {
        "CreatedOnToolsVersion": "16.0",
    }
    objs[proj["mainGroup"]]  # touch
    for uid, obj in objs.items():
        if obj.get("isa") == "PBXGroup" and obj.get("name") == "Products":
            obj["children"].append(U["app_ref"])
            break

    print("✅  App target → Developer ID (non-sandbox, hardened runtime);"
          " added AerialLandscapesMacMAS (sandboxed, MAS flag)")


if __name__ == "__main__":
    shutil.copy(PBXPROJ, PBXPROJ + ".bak")
    data = load()
    patch(data)
    save(data)
