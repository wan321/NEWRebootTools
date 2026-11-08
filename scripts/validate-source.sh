#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

command -v plutil >/dev/null || { echo 'plutil not found' >&2; exit 1; }
command -v lipo >/dev/null || { echo 'lipo not found' >&2; exit 1; }

plutil -lint Resources/Info.plist
for helper in Resources/RebootRootHelper Resources/RebootUserSpaceHelper; do
  test -s "$helper" || { echo "Missing helper: $helper" >&2; exit 1; }
  lipo -verify_arch arm64 "$helper"
  test -x "$helper" || { echo "Helper is not executable: $helper" >&2; exit 1; }
done

grep -q 'reboottools' Resources/Info.plist || { echo 'URL scheme missing from Info.plist' >&2; exit 1; }
grep -q 'RebootTools_RESOURCE_DIRS = Resources' Makefile || { echo 'Resources directory is not configured for bundle copying' >&2; exit 1; }
echo 'Source validation passed.'
