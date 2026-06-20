#!/usr/bin/env python3
"""
Add AerialLandscapesIOS target to AerialLandscapes.xcodeproj.
Converts pbxproj → XML → patches → converts back to OpenStep format.
"""
import plistlib, subprocess, shutil, os, sys

PBXPROJ = os.path.join(os.path.dirname(__file__),
                        "AerialLandscapes.xcodeproj", "project.pbxproj")
XML_TMP  = "/tmp/project_ios_patch.xml"
TEAM     = "D2GRT69L42"
BUNDLE   = "com.pjloury.aerial-landscapes-ios"
TARGET   = "AerialLandscapesIOS"

# ── Deterministic 24-char Xcode-style UUIDs ───────────────
U = {
    "app_ref":      "BB0001010000000000000001",
    "app_swift":    "BB0001020000000000000001",
    "content_swift":"BB0001030000000000000001",
    "webview_swift":"BB0001040000000000000001",
    "assets":       "BB0001050000000000000001",
    "group":        "BB0001060000000000000001",
    "src_phase":    "BB0001070000000000000001",
    "fw_phase":     "BB0001080000000000000001",
    "res_phase":    "BB0001090000000000000001",
    "target":       "BB0001100000000000000001",
    "debug_cfg":    "BB0001110000000000000001",
    "release_cfg":  "BB0001120000000000000001",
    "cfg_list":     "BB0001130000000000000001",
    "bf_app":       "BB0001200000000000000001",
    "bf_content":   "BB0001210000000000000001",
    "bf_webview":   "BB0001220000000000000001",
    "bf_assets":    "BB0001230000000000000001",
}

def convert(src, dst, fmt):
    subprocess.run(["plutil", "-convert", fmt, src, "-o", dst], check=True)

def load():
    convert(PBXPROJ, XML_TMP, "xml1")
    with open(XML_TMP, "rb") as f:
        return plistlib.load(f)

def save(data):
    # Write as XML plist — Xcode accepts pbxproj in XML format
    with open(PBXPROJ, "wb") as f:
        plistlib.dump(data, f)

def build_settings(extra=None):
    base = {
        "SDKROOT": "iphoneos",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": TEAM,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE,
        "MARKETING_VERSION": "1.0",
        "CURRENT_PROJECT_VERSION": "1",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UIStatusBarStyle": "UIStatusBarStyleLightContent",
        "INFOPLIST_KEY_UIViewControllerBasedStatusBarAppearance": "NO",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "PRODUCT_NAME": "$(TARGET_NAME)",
    }
    if extra:
        base.update(extra)
    return base

def patch(data):
    objs = data["objects"]

    # Guard: already patched
    if U["target"] in objs:
        print("iOS target already present — nothing to do.")
        sys.exit(0)

    # ── File references ────────────────────────────────────
    objs[U["app_ref"]] = {
        "isa": "PBXFileReference",
        "explicitFileType": "wrapper.application",
        "includeInIndex": "0",
        "path": f"{TARGET}.app",
        "sourceTree": "BUILT_PRODUCTS_DIR",
    }
    src_files = {
        U["app_swift"]:     ("App.swift",         "sourcecode.swift"),
        U["content_swift"]: ("ContentView.swift",  "sourcecode.swift"),
        U["webview_swift"]: ("WebView.swift",       "sourcecode.swift"),
    }
    for uid, (name, ftype) in src_files.items():
        objs[uid] = {
            "isa": "PBXFileReference",
            "fileEncoding": "4",
            "lastKnownFileType": ftype,
            "name": name,
            "path": name,  # relative to group path
            "sourceTree": "<group>",
        }
    objs[U["assets"]] = {
        "isa": "PBXFileReference",
        "lastKnownFileType": "folder.assetcatalog",
        "name": "Assets.xcassets",
        "path": "Resources/Assets.xcassets",  # relative to group path
        "sourceTree": "<group>",
    }

    # ── Build files ────────────────────────────────────────
    build_file_map = {
        U["bf_app"]:     U["app_swift"],
        U["bf_content"]: U["content_swift"],
        U["bf_webview"]: U["webview_swift"],
        U["bf_assets"]:  U["assets"],
    }
    for bf_uid, ref_uid in build_file_map.items():
        objs[bf_uid] = {
            "isa": "PBXBuildFile",
            "fileRef": ref_uid,
        }

    # ── Group ──────────────────────────────────────────────
    objs[U["group"]] = {
        "isa": "PBXGroup",
        "children": [U["app_swift"], U["content_swift"], U["webview_swift"], U["assets"]],
        "name": TARGET,
        "path": "AerialLandscapesIOS",
        "sourceTree": "<group>",
    }

    # ── Build phases ───────────────────────────────────────
    objs[U["src_phase"]] = {
        "isa": "PBXSourcesBuildPhase",
        "buildActionMask": "2147483647",
        "files": [U["bf_app"], U["bf_content"], U["bf_webview"]],
        "runOnlyForDeploymentPostprocessing": "0",
    }
    objs[U["fw_phase"]] = {
        "isa": "PBXFrameworksBuildPhase",
        "buildActionMask": "2147483647",
        "files": [],
        "runOnlyForDeploymentPostprocessing": "0",
    }
    objs[U["res_phase"]] = {
        "isa": "PBXResourcesBuildPhase",
        "buildActionMask": "2147483647",
        "files": [U["bf_assets"]],
        "runOnlyForDeploymentPostprocessing": "0",
    }

    # ── Build configurations ───────────────────────────────
    objs[U["debug_cfg"]] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": build_settings({"DEBUG_INFORMATION_FORMAT": "dwarf"}),
        "name": "Debug",
    }
    objs[U["release_cfg"]] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": build_settings({"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym"}),
        "name": "Release",
    }
    objs[U["cfg_list"]] = {
        "isa": "XCConfigurationList",
        "buildConfigurations": [U["debug_cfg"], U["release_cfg"]],
        "defaultConfigurationIsVisible": "0",
        "defaultConfigurationName": "Release",
    }

    # ── Native target ──────────────────────────────────────
    objs[U["target"]] = {
        "isa": "PBXNativeTarget",
        "buildConfigurationList": U["cfg_list"],
        "buildPhases": [U["src_phase"], U["fw_phase"], U["res_phase"]],
        "buildRules": [],
        "dependencies": [],
        "name": TARGET,
        "productName": TARGET,
        "productReference": U["app_ref"],
        "productType": "com.apple.product-type.application",
    }

    # ── Wire into project ──────────────────────────────────
    # Add target to PBXProject
    proj_uid = data["rootObject"]
    data["objects"][proj_uid]["targets"].append(U["target"])

    # Add group to main group children
    main_group_uid = data["objects"][proj_uid]["mainGroup"]
    main_group = data["objects"][main_group_uid]
    main_group["children"].append(U["group"])

    # Add product to Products group
    for uid, obj in data["objects"].items():
        if obj.get("isa") == "PBXGroup" and obj.get("name") == "Products":
            obj["children"].append(U["app_ref"])
            break

    print(f"✅  Patched project — added target '{TARGET}'")

if __name__ == "__main__":
    shutil.copy(PBXPROJ, PBXPROJ + ".bak")
    data = load()
    patch(data)
    save(data)
