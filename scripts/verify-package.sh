#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p dist
rm -f dist/RebootTools-Shortcuts.tipa
shopt -s nullglob
packages=(packages/*.ipa packages/*.tipa)
if (( ${#packages[@]} == 0 )); then
  echo 'No .ipa/.tipa package was produced in packages/.' >&2
  exit 1
fi

# Prefer the first package emitted by Theos; package naming can vary by Theos version.
source_package="${packages[0]}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
unzip -q "$source_package" -d "$tmpdir"
app="$tmpdir/Payload/RebootTools.app"
test -d "$app" || { echo 'Payload/RebootTools.app is missing.' >&2; exit 1; }
for helper in \
  "$APP_PATH/RebootRootHelper" \
  "$APP_PATH/RebootUserSpaceHelper"
do
  if [ ! -s "$helper" ]; then
    echo "Missing helper: $helper" >&2
    exit 1
  fi

  echo "Checking architecture: $helper"
  lipo "$helper" -verify_arch arm64

  chmod +x "$helper"

  if [ ! -x "$helper" ]; then
    echo "Helper is not executable: $helper" >&2
    exit 1
  fi

  echo "Helper OK: $helper"
done
/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$app/Info.plist" | grep -qx 'reboottools'
cp "$source_package" dist/RebootTools-Shortcuts.tipa
ls -lh dist/RebootTools-Shortcuts.tipa
echo 'Package structure validation passed. Device installation/reboot still requires on-device testing.'
