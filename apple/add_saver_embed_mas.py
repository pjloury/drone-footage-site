#!/usr/bin/env python3
"""
Embed AerialLandscapesSaver.saver inside the App Store build
("Aerial Landscapes.app", target AerialLandscapesMacMAS) under Contents/
PlugIns, and make that target depend on the saver target so it builds first.

This mirrors add_saver_embed.py (which does the same for the Dev ID target).
The MAS app can't auto-install the saver from inside the sandbox, so it ships
the .saver and the "Set Up Screen Saver…" menu item copies it to ~/Downloads
for the user to double-click. Run AFTER add_saver_target.py.
"""
import plistlib, subprocess, shutil, os, sys

PBXPROJ = os.path.join(os.path.dirname(__file__),
                       "AerialLandscapes.xcodeproj", "project.pbxproj")
XML_TMP = "/tmp/project_saver_embed_mas.xml"

MAS_APP_TARGET = "DD0001070000000000000001"
SAVER_TARGET   = "CC0001090000000000000001"
SAVER_PRODUCT  = "CC0001020000000000000001"  # AerialLandscapesSaver.saver ref

U = {
    "embed_phase":   "DD0002000000000000000001",
    "bf_saver":      "DD0002010000000000000001",  # PBXBuildFile for embed
    "dep":           "DD0002020000000000000001",  # PBXTargetDependency
    "container":     "DD0002030000000000000001",  # PBXContainerItemProxy
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


def patch(data):
    objs = data["objects"]
    if U["embed_phase"] in objs:
        print("MAS embed phase already present — nothing to do.")
        sys.exit(0)

    project_container = data["rootObject"]

    # Build file that copies the saver, with code-sign-on-copy.
    objs[U["bf_saver"]] = {
        "isa": "PBXBuildFile",
        "fileRef": SAVER_PRODUCT,
        "settings": {"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]},
    }

    # Copy Files phase → PlugIns (dstSubfolderSpec 13).
    objs[U["embed_phase"]] = {
        "isa": "PBXCopyFilesBuildPhase",
        "buildActionMask": "2147483647",
        "dstPath": "",
        "dstSubfolderSpec": "13",
        "files": [U["bf_saver"]],
        "name": "Embed Screen Saver",
        "runOnlyForDeploymentPostprocessing": "0",
    }

    # Dependency: MAS app target depends on saver target so it builds first.
    objs[U["container"]] = {
        "isa": "PBXContainerItemProxy",
        "containerPortal": project_container,
        "proxyType": "1",
        "remoteGlobalIDString": SAVER_TARGET,
        "remoteInfo": "AerialLandscapesSaver",
    }
    objs[U["dep"]] = {
        "isa": "PBXTargetDependency",
        "target": SAVER_TARGET,
        "targetProxy": U["container"],
    }

    app = objs[MAS_APP_TARGET]
    app["buildPhases"].append(U["embed_phase"])
    app.setdefault("dependencies", []).append(U["dep"])

    print("✅  Embedded saver into MAS app PlugIns + added build dependency")


if __name__ == "__main__":
    shutil.copy(PBXPROJ, PBXPROJ + ".bak_mas_embed")
    data = load()
    patch(data)
    save(data)
