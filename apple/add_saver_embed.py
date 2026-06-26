#!/usr/bin/env python3
"""
Embed AerialLandscapesSaver.saver inside AerialLandscapesMac.app (Contents/
PlugIns) and make the app depend on the saver target so it's built first.
Run AFTER add_saver_target.py.
"""
import plistlib, subprocess, shutil, os, sys

PBXPROJ = os.path.join(os.path.dirname(__file__),
                       "AerialLandscapes.xcodeproj", "project.pbxproj")
XML_TMP = "/tmp/project_saver_embed.xml"

MAC_APP_TARGET = "AA0001062D238122004DA734"
SAVER_TARGET   = "CC0001090000000000000001"
SAVER_PRODUCT  = "CC0001020000000000000001"  # AerialLandscapesSaver.saver ref

U = {
    "embed_phase":   "CC0002000000000000000001",
    "bf_saver":      "CC0002010000000000000001",  # PBXBuildFile for embed
    "dep":           "CC0002020000000000000001",  # PBXTargetDependency
    "container":     "CC0002030000000000000001",  # PBXContainerItemProxy
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
        print("Embed phase already present — nothing to do.")
        sys.exit(0)

    proj_uid = data["rootObject"]
    root_object = objs[proj_uid]
    project_container = proj_uid

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

    # Dependency: app target depends on saver target so it builds first.
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

    app = objs[MAC_APP_TARGET]
    app["buildPhases"].append(U["embed_phase"])
    app.setdefault("dependencies", []).append(U["dep"])

    print("✅  Embedded saver into app PlugIns + added build dependency")
    _ = root_object  # silence lint


if __name__ == "__main__":
    shutil.copy(PBXPROJ, PBXPROJ + ".bak2")
    data = load()
    patch(data)
    save(data)
