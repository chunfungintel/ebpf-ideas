#!/usr/bin/env bash
# Clones the Ubuntu kernel source tree matching the running kernel (or an
# explicitly given release/version) and checks out the tag for that exact
# build, using Canonical's official mirror.
#
# With no arguments, detects codename and version from the current machine
# via lsb_release and dpkg. Pass both explicitly to target a different
# machine's kernel (e.g. checking values gathered from inside a VM).
set -euo pipefail

usage() {
	cat <<EOF
Usage: $0 [codename kernel-version] [dest-dir]

  codename        Ubuntu release codename, e.g. noble, jammy, focal
                  (default: autodetected via lsb_release -cs)
  kernel-version  Version from: dpkg -s linux-image-\$(uname -r)
                  (default: autodetected; the ~XX.04.1 suffix is stripped)
  dest-dir        Where to clone to (default: ./ubuntu-<codename>)

Example:
  $0                                       # clone/checkout this machine's kernel
  $0 noble 6.17.0-35.35~24.04.1            # clone/checkout an explicit build
  $0 noble 6.17.0-35.35 ~/src/ubuntu-noble
EOF
	exit 1
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

if [[ $# -eq 0 || $# -eq 1 ]]; then
	CODENAME="$(lsb_release -cs)"
	VERSION_RAW="$(dpkg -s "linux-image-$(uname -r)" | grep ^Version: | awk '{print $2}')"
	VERSION="${VERSION_RAW%%~*}"
	DEST="${1:-./ubuntu-$CODENAME}"
	echo "Autodetected: codename=$CODENAME version=$VERSION_RAW"
elif [[ $# -ge 2 ]]; then
	CODENAME="$1"
	VERSION="${2%%~*}"
	DEST="${3:-./ubuntu-$CODENAME}"
else
	usage
fi

REPO="https://kernel.ubuntu.com/git/ubuntu/ubuntu-${CODENAME}.git"

echo "[1/3] Looking up tag for version $VERSION on $REPO ..."
TAG="$(git ls-remote --tags "$REPO" "Ubuntu-${VERSION}*" | awk '{print $2}' | sed -e 's#refs/tags/##' -e 's/\^{}$//' | sort -uV | tail -1)"

if [[ -z "$TAG" ]]; then
	echo "error: no tag found matching Ubuntu-${VERSION}*" >&2
	echo "Nearby tags:" >&2
	MAJOR_MINOR="$(echo "$VERSION" | cut -d. -f1-2)"
	git ls-remote --tags "$REPO" "Ubuntu-${MAJOR_MINOR}*" | awk '{print $2}' | sed -e 's#refs/tags/##' -e 's/\^{}$//' | sort -uV >&2
	exit 1
fi

echo "[2/3] Found tag: $TAG"

echo "[3/3] Shallow-cloning $TAG into $DEST ..."
git clone --depth 1 --branch "$TAG" "$REPO" "$DEST"

echo
echo "Done. Source is checked out at: $DEST"
