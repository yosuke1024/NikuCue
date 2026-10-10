#!/bin/sh
# Xcode run-script phase: a Release build must not ship placeholder identifiers (docs/06 §7, QA Q36).
# Debug builds pass so local development with mocks keeps working.
set -eu
if [ "${CONFIGURATION:-Debug}" != "Release" ]; then
  echo "check_release_config: ${CONFIGURATION:-Debug} build, placeholders allowed"
  exit 0
fi
SRC="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
if grep -q "REPLACE_WITH_" "$SRC/NikuCue/App/AppConfiguration.swift"; then
  echo "error: AppConfiguration.swift still contains REPLACE_WITH_ placeholders; Release builds are blocked until the owner sets real identifiers (R05–R09)."
  exit 1
fi
case "${PRODUCT_BUNDLE_IDENTIFIER:-}" in
  *placeholder*) echo "error: PRODUCT_BUNDLE_IDENTIFIER '$PRODUCT_BUNDLE_IDENTIFIER' is a placeholder (R05)."; exit 1 ;;
esac
echo "check_release_config: ok"
