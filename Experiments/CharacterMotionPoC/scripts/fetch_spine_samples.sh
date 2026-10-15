#!/bin/sh
# Downloads the official Spine "spineboy" sample (evaluation only) from the pinned spine-runtimes commit,
# verifies SHA-256, and copies it into the git-ignored resource folders of the iOS app and the web harness.
#
# The sample images are licensed by Esoteric Software for non-commercial use only (examples/spineboy/license.txt):
# they are NOT product assets, are never committed to this repository and must never ship in NikuCue.
set -eu

COMMIT="b7beb2ccbbce667a12c02f44d070644f59b04968"   # tag spine-ts-4.3.13 (2026-07-24), same snapshot as the pinned runtimes
BASE="https://raw.githubusercontent.com/EsotericSoftware/spine-runtimes/${COMMIT}/examples/spineboy"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${ROOT}/.samples-cache"
mkdir -p "${CACHE}"

fetch() { # path sha256
  name="$(basename "$1")"
  if [ ! -f "${CACHE}/${name}" ] || ! echo "$2  ${CACHE}/${name}" | shasum -a 256 -c - >/dev/null 2>&1; then
    curl -sS -fL --retry 3 -o "${CACHE}/${name}" "${BASE}/$1"
  fi
  echo "$2  ${CACHE}/${name}" | shasum -a 256 -c - >/dev/null || { echo "SHA-256 mismatch: ${name}" >&2; exit 1; }
}

fetch export/spineboy-pro.json  24ccffc13e334e721dfd427ee2b8aea05c25b59167b5fb0bb0f9685e11d2a7d3
fetch export/spineboy-pro.skel  e10de3f2473a37139c3ad1fda14e84b29ef401475ec9fa2129e7d2a311088845
fetch export/spineboy-pma.atlas b04b98b6ac9e28ee1cf660e4d96d6c7df21fbd5d47aa2382c84865ff18795db8
fetch export/spineboy-pma.png   47bab0de0518a5b7daa829d953439972c5d43b78fc31b40e1557a2ed625a00b5
fetch license.txt               08074c5f8c5f072626a0830250304fe3063d9d49f8f9b039e063bb238f2b993b

for dest in "${ROOT}/MotionLab/MotionLab/SpineSamples" "${ROOT}/web/samples"; do
  mkdir -p "${dest}"
  cp "${CACHE}/spineboy-pro.skel" "${CACHE}/spineboy-pro.json" "${CACHE}/spineboy-pma.atlas" "${CACHE}/spineboy-pma.png" "${dest}/"
  cp "${CACHE}/license.txt" "${dest}/spineboy-license.txt"
done
echo "spineboy sample ready (commit ${COMMIT}); evaluation only, not a product asset"
