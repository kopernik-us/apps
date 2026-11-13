#!/usr/bin/env bash
#
# Builds and publishes the image of an app from its directory apps/<uid>/: the image the machines of a customer's
# app pull when they run that application. The digest it pushed is pinned in the app's template.json, which is
# left for you to commit.
#
# Usage: apps/publish.sh <uid> [VERSION]    (default: the template's first version)
#
# These are not the images of scripts/build.sh, and REGISTRY and KUBE_CONTEXT do not apply here. A component
# image is tagged with a kopernik commit and pushed to the registry the cluster deploys from; an application
# image is tagged with the application's own version and pushed to the public registry named in the
# template, because what pulls it is a customer's machine rather than our cluster. See apps/README.md.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/common.sh"

# Platforms an application image is published for. A machine runs the architecture its owner chose a machine
# type for, and a single-platform image fails at pull time on the others, so both are published unless the
# image says otherwise in a platforms file of its own, which is how an image whose base offers one
# architecture records that rather than leaving it to be remembered on the command line.
DEFAULT_PLATFORMS="linux/amd64,linux/arm64"

name="${1:-}"
[ -n "$name" ] || fail "usage: apps/publish.sh <uid> [VERSION]"
wanted_version="${2:-}"

app_dir="$REPO_ROOT/apps/$name"
template="$app_dir/template.json"
[ -f "$template" ] || fail "no app at apps/$name: it has no template.json"
[ -f "$app_dir/Dockerfile" ] || fail "apps/$name has no Dockerfile: its template runs an upstream image"
if [ -n "${PLATFORMS:-}" ]; then
    platforms="$PLATFORMS"
elif [ -f "$app_dir/platforms" ]; then
    platforms="$(tr '\n' ',' <"$app_dir/platforms" | sed 's/,*$//')"
else
    platforms="$DEFAULT_PLATFORMS"
fi
command -v python3 >/dev/null || fail "python3 is required to read the template"

# An image a customer pulls must be reproducible from a commit: the tag names an application version rather
# than a tree, so a rebuilt tag which is not the one published cannot be told apart afterwards.
is_tree_clean || fail "the working tree has uncommitted changes; commit or stash them before publishing"

# The tag is the template's, not this script's: a create request is rejected unless its image matches a
# template version exactly, so the ref the template declares is the only one worth pushing.
resolved="$(python3 - "$template" "$wanted_version" <<'PY'
import json
import sys

template, wanted = sys.argv[1], sys.argv[2]
with open(template) as source:
    versions = json.load(source).get("versions") or []
if not versions:
    sys.exit("error: the template declares no version")
if wanted:
    declared = [version for version in versions if version.get("version") == wanted]
    if not declared:
        sys.exit("error: the template declares no version %s, only %s"
                 % (wanted, ", ".join(str(version.get("version")) for version in versions)))
else:
    declared = versions[:1]
image = (declared[0].get("image") or {}).get("id")
if not image:
    sys.exit("error: version %s names no image" % declared[0].get("version"))
print(declared[0]["version"])
print(image)
PY
)" || exit 1
version="$(sed -n 1p <<<"$resolved")"
image="$(sed -n 2p <<<"$resolved")"

# A ref whose first segment names no host belongs to Docker Hub, which we cannot push to and which would
# leave the template pointing at an image nobody published.
host="${image%%/*}"
if [ "$host" = "$image" ]; then
    fail "the template's image '$image' names no registry to publish to"
fi
case "$host" in
    *.* | *:*) ;;
    *) fail "the template's image '$image' names no registry to publish to" ;;
esac

echo "Publishing $name $version as $image for $platforms"
metadata="$(mktemp)"
trap 'rm -f "$metadata"' EXIT
docker buildx build \
    --platform "$platforms" \
    --build-arg "VERSION=$version" \
    --label "org.opencontainers.image.source=https://github.com/kopernik-us/kopernik.us" \
    --label "org.opencontainers.image.revision=$(git -C "$REPO_ROOT" rev-parse HEAD)" \
    --label "org.opencontainers.image.version=$version" \
    --metadata-file "$metadata" \
    --push \
    -t "$image" \
    "$app_dir"

digest="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("containerimage.digest", ""))' \
    "$metadata")"
[ -n "$digest" ] || fail "the build reported no digest for $image, so the template could not be pinned"

# The digest is written where the version names its image, as an edit of that one entry rather than a rewrite of
# the file, so that the pin is the only change in the diff to commit.
python3 - "$template" "$image" "$digest" <<'PY'
import json
import re
import sys

template, image, digest = sys.argv[1:]
with open(template) as source:
    text = source.read()
entry = re.compile(r'(?m)^([ \t]*)"id":\s*"%s"(\s*,\s*"digest":\s*"[^"]*")?' % re.escape(image))
matches = list(entry.finditer(text))
if len(matches) != 1:
    sys.exit("error: %s names image %s %d times rather than once; pin %s by hand"
             % (template, image, len(matches), digest))
indent = matches[0].group(1)
pinned = '%s"id": "%s",\n%s"digest": "%s"' % (indent, image, indent, digest)
text = text[:matches[0].start()] + pinned + text[matches[0].end():]
images = [version.get("image") or {} for version in json.loads(text).get("versions") or []]
if not any(found.get("id") == image and found.get("digest") == digest for found in images):
    sys.exit("error: %s did not take the digest; pin %s by hand" % (template, digest))
with open(template, "w") as target:
    target.write(text)
PY

echo
echo "Published $image"
echo "Pinned $digest in ${template#"$REPO_ROOT/"}: commit it, so that a machine pulls this exact image."
echo
echo "A package is private until it is made public, and a private one is unusable: a customer's machine"
echo "pulls anonymously. Check the package's visibility at https://github.com/orgs/kopernik-us/packages"
