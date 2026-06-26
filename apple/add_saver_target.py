#!/usr/bin/env python3
"""
Add the AerialLandscapesSaver (.saver screensaver) target to
AerialLandscapes.xcodeproj, and share the MacEngine/ folder between the
existing AerialLandscapesMac app and the new saver target.

Mirrors add_ios_target.py: pbxproj -> XML -> patch -> XML plist (Xcode
re-normalises to OpenStep on next save).
"""
import plistlib, subprocess, shutil, os, sys

PBXPROJ = os.path.join(os.path.dirname(__file__),
                       "AerialLandscapes.xcodeproj", "project.pbxproj")
XML_TMP = "/tmp/project_saver_patch.xml"
TEAM    = "D2GRT69L42"
BUNDLE  = "com.pjloury.aerial-landscapes-saver"
TARGET  = "AerialLandscapesSaver"

MAC_APP_TARGET = "AA0001062D238122004DA734"  # AerialLandscapesMac native target

U = {
    "engine_group":  "CC0001000000000000000001",  # MacEngine synced folder
    "saver_group":   "CC0001010000000000000001",  # MacScreenSaver synced folder
    "saver_ref":     "CC0001020000000000000001",  # product .saver
    "src_phase":     "CC0001030000000000000001",
    "fw_phase":      "CC0001040000000000000001",
    "res_phase":     "CC0001050000000000000001",
    "debug_cfg":     "CC0001060000000000000001",
    "release_cfg":   "CC0001070000000000000001",
    "cfg_list":      "CC0001080000000000000001",
    "target":        "CC0001090000000000000001",
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


def build_settings(extra=None):
    base = {
        "SDKROOT": "macosx",
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": TEAM,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE,
        "PRODUCT_NAME": TARGET,
        "WRAPPER_EXTENSION": "saver",
        "MARKETING_VERSION": "1.0",
        "CURRENT_PROJECT_VERSION": "1",
        "SWIFT_VERSION": "5.0",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_NSPrincipalClass": "AerialScreenSaverView",
        "INFOPLIST_KEY_CFBundleDisplayName": "Aerial Landscapes",
        "INFOPLIST_KEY_NSHumanReadableCopyright": "Aerial Landscapes",
        "SKIP_INSTALL": "YES",
        "COMBINE_HIDPI_IMAGES": "YES",
        "DEAD_CODE_STRIPPING": "YES",
        "LD_RUNPATH_SEARCH_PATHS": [
            "$(inherited)",
            "@executable_path/../Frameworks",
            "@loader_path/../Frameworks",
        ],
    }
    if extra:
        base.update(extra)
    return base


def patch(data):
    objs = data["objects"]
    if U["target"] in objs:
        print("Saver target already present — nothing to do.")
        sys.exit(0)

    # ── Synced folder groups ───────────────────────────────
    objs[U["engine_group"]] = {
        "isa": "PBXFileSystemSynchronizedRootGroup",
        "path": "MacEngine",
        "sourceTree": "<group>",
    }
    objs[U["saver_group"]] = {
        "isa": "PBXFileSystemSynchronizedRootGroup",
        "path": "MacScreenSaver",
        "sourceTree": "<group>",
    }

    # ── Product reference ──────────────────────────────────
    objs[U["saver_ref"]] = {
        "isa": "PBXFileReference",
        "explicitFileType": "wrapper.cfbundle",
        "includeInIndex": "0",
        "path": f"{TARGET}.saver",
        "sourceTree": "BUILT_PRODUCTS_DIR",
    }

    # ── Build phases (sources come from synced groups → empty) ──
    objs[U["src_phase"]] = {
        "isa": "PBXSourcesBuildPhase", "buildActionMask": "2147483647",
        "files": [], "runOnlyForDeploymentPostprocessing": "0",
    }
    objs[U["fw_phase"]] = {
        "isa": "PBXFrameworksBuildPhase", "buildActionMask": "2147483647",
        "files": [], "runOnlyForDeploymentPostprocessing": "0",
    }
    objs[U["res_phase"]] = {
        "isa": "PBXResourcesBuildPhase", "buildActionMask": "2147483647",
        "files": [], "runOnlyForDeploymentPostprocessing": "0",
    }

    # ── Build configs ──────────────────────────────────────
    objs[U["debug_cfg"]] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": build_settings({"DEBUG_INFORMATION_FORMAT": "dwarf"}),
        "name": "Debug",
    }
    objs[U["release_cfg"]] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": build_settings({
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
            "SWIFT_COMPILATION_MODE": "wholemodule",
        }),
        "name": "Release",
    }
    objs[U["cfg_list"]] = {
        "isa": "XCConfigurationList",
        "buildConfigurations": [U["debug_cfg"], U["release_cfg"]],
        "defaultConfigurationIsVisible": "0",
        "defaultConfigurationName": "Release",
    }

    # ── Native target (loadable bundle = screensaver) ──────
    objs[U["target"]] = {
        "isa": "PBXNativeTarget",
        "buildConfigurationList": U["cfg_list"],
        "buildPhases": [U["src_phase"], U["fw_phase"], U["res_phase"]],
        "buildRules": [],
        "dependencies": [],
        "fileSystemSynchronizedGroups": [U["saver_group"], U["engine_group"]],
        "name": TARGET,
        "productName": TARGET,
        "productReference": U["saver_ref"],
        "productType": "com.apple.product-type.bundle",
    }

    # ── Wire into project ──────────────────────────────────
    proj_uid = data["rootObject"]
    proj = objs[proj_uid]
    proj["targets"].append(U["target"])
    proj.setdefault("attributes", {}).setdefault("TargetAttributes", {})[U["target"]] = {
        "CreatedOnToolsVersion": "16.0",
    }

    # MacEngine becomes a member of the existing Mac app target too, so the
    # moved engine files still compile there.
    app = objs[MAC_APP_TARGET]
    app.setdefault("fileSystemSynchronizedGroups", [])
    if U["engine_group"] not in app["fileSystemSynchronizedGroups"]:
        app["fileSystemSynchronizedGroups"].append(U["engine_group"])

    # Add folder groups to the main group, product to Products.
    main_group = objs[proj["mainGroup"]]
    for g in (U["engine_group"], U["saver_group"]):
        if g not in main_group["children"]:
            main_group["children"].append(g)
    for uid, obj in objs.items():
        if obj.get("isa") == "PBXGroup" and obj.get("name") == "Products":
            obj["children"].append(U["saver_ref"])
            break

    print(f"✅  Patched project — added target '{TARGET}' + shared MacEngine group")


if __name__ == "__main__":
    shutil.copy(PBXPROJ, PBXPROJ + ".bak")
    data = load()
    patch(data)
    save(data)
