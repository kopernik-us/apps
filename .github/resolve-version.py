#!/usr/bin/env python3
"""Reads the version of an app to build from its template, and prints what building it takes as name=value lines.

Usage: resolve-version.py <app> [VERSION]    (default: the template's latest version, which it lists last)

The image ref is the template's, not the caller's: an app is created only from an image matching a version of its
template exactly, so the ref the template names is the only one worth pushing, and it must be
ghcr.io/<owner>/<app>:<version>, the owner taken from GITHUB_REPOSITORY_OWNER (kopernik-us when unset). So are the
platforms: a version states the architectures its image runs on, and an image built for fewer fails on the machines
of the others.

Prints version, image (the tagged ref), repository (the ref without its tag), context (the directory the image is
built from) and platforms (comma separated, as docker buildx names them).
"""

import json
import os
import re
import sys
from pathlib import Path

PLATFORMS = {"x86_64": "linux/amd64", "arm64": "linux/arm64"}
NAME = re.compile(r"[a-z0-9]+(-[a-z0-9]+)*")
VERSION = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")


def fail(message):
    sys.exit("error: " + message)


def main(argv):
    if len(argv) not in (2, 3):
        fail("usage: resolve-version.py <app> [VERSION]")
    app = argv[1]
    wanted = argv[2] if len(argv) == 3 else ""
    if not NAME.fullmatch(app):
        fail("%r is no app name: lowercase letters and digits, joined by single hyphens" % app)

    root = Path(__file__).resolve().parent.parent
    template_path = root / app / "template.json"
    if not template_path.is_file():
        fail("no app %s: it has no template.json" % app)
    versions = json.loads(template_path.read_text()).get("versions") or []
    if not versions:
        fail("the template of %s declares no version" % app)

    if wanted:
        declared = [version for version in versions if version.get("version") == wanted]
        if not declared:
            fail("the template of %s declares no version %s, only %s"
                 % (app, wanted, ", ".join(str(version.get("version")) for version in versions)))
        version = declared[0]
    else:
        version = versions[-1]
    name = str(version.get("version"))
    if not VERSION.fullmatch(name):
        fail("%s names a version %r which is no directory name" % (app, name))

    context = root / app / name
    if not (context / "Dockerfile").is_file():
        fail("%s/%s has no Dockerfile: the template runs an upstream image for %s" % (app, name, name))

    owner = os.environ.get("GITHUB_REPOSITORY_OWNER") or "kopernik-us"
    repository = "ghcr.io/%s/%s" % (owner.lower(), app)
    image = (version.get("image") or {}).get("id")
    if image != "%s:%s" % (repository, name):
        fail("%s %s names image %r rather than %s:%s, the ref its directory is published as"
             % (app, name, image, repository, name))

    architectures = version.get("architectures") or []
    if not architectures:
        fail("%s %s states no architectures to build for" % (app, name))
    unknown = [architecture for architecture in architectures if architecture not in PLATFORMS]
    if unknown:
        fail("%s %s states architectures no platform is known for: %s" % (app, name, ", ".join(unknown)))

    print("version=%s" % name)
    print("image=%s" % image)
    print("repository=%s" % repository)
    print("context=%s" % context.relative_to(root))
    print("platforms=%s" % ",".join(PLATFORMS[architecture] for architecture in architectures))


if __name__ == "__main__":
    main(sys.argv)
