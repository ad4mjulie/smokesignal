#!/usr/bin/env bash
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$IOS_DIR/SmokeSignal.xcodeproj"
SCHEME="SmokeSignal"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/smokesignal-deriveddata}"

DATA_VOLUME="${DATA_VOLUME:-/System/Volumes/Data}"
MIN_FREE_GB="${MIN_FREE_GB:-2}"
DEVICE_TIMEOUT="${DEVICE_TIMEOUT:-120}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "SmokeSignal Xcode project not found at: $PROJECT_PATH"
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install Xcode from the Mac App Store first."
  exit 1
fi

XCODE_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
DEVICE_SUPPORT_DIR="${XCODE_DEV_DIR}/Platforms/iPhoneOS.platform/DeviceSupport"
if [[ -d "$DEVICE_SUPPORT_DIR" ]]; then
  if ! find "$DEVICE_SUPPORT_DIR" -maxdepth 2 -type f -name "DeveloperDiskImage.dmg" -path "*/26.*/*" 2>/dev/null | head -n 1 | grep -q .; then
    echo "Note: Xcode does not appear to have iOS 26.x device support installed yet."
    echo "If you see 'iOS 26.2 is not installed', open Xcode -> Settings -> Components and install iOS 26.2."
    echo
  fi
fi

maybe_cleanup_disk_space() {
  if [[ ! -d "$DATA_VOLUME" ]]; then
    return 0
  fi

  local free_kb
  free_kb="$(df -k "$DATA_VOLUME" 2>/dev/null | awk 'NR==2 {print $4}')"
  if [[ -z "${free_kb:-}" ]]; then
    return 0
  fi

  local min_free_kb=$((MIN_FREE_GB * 1024 * 1024))
  if (( free_kb >= min_free_kb )); then
    return 0
  fi

  local free_mb=$((free_kb / 1024))
  echo "Low disk space: ~${free_mb}MB free on $DATA_VOLUME."
  echo "Xcode device tools often fail when disk is nearly full."
  echo
  echo "Safe cleanup is Xcode caches (they will be re-created automatically):"
  du -sh "$HOME/Library/Developer/Xcode/iOS DeviceSupport" 2>/dev/null || true
  du -sh "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null || true
  echo

  local reply="n"
  if [[ "${AUTO_CLEAN:-}" == "1" || "${AUTO_CLEAN:-}" == "true" ]]; then
    reply="y"
  else
    read -r -p "Delete those Xcode caches now to free space? [y/N] " reply || true
  fi

  if [[ "$reply" != "y" && "$reply" != "Y" ]]; then
    echo "Free at least ${MIN_FREE_GB}GB of disk space, then re-run:"
    echo "  ./run_on_iphone.sh"
    exit 1
  fi

  echo "Deleting Xcode caches..."
  rm -rf \
    "$HOME/Library/Developer/Xcode/DerivedData" \
    "$HOME/Library/Developer/Xcode/iOS DeviceSupport" \
    "$HOME/Library/Developer/Xcode/Archives" \
    "$HOME/Library/Developer/CoreSimulator" \
    "$HOME/Library/Logs/CoreSimulator" \
    || true

  echo "Disk space after cleanup:"
  df -h "$DATA_VOLUME" 2>/dev/null || true
  echo
}

detect_team_id() {
  # Requires you to sign into Xcode once (Xcode -> Settings -> Accounts).
  defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | awk '/teamID/ {gsub(/;/, "", $3); print $3; exit}'
}

detect_device_id_xcdevice() {
  xcrun xcdevice list 2>/dev/null \
    | python3 - <<'PY'
import json, sys
try:
  devices = json.loads(sys.stdin.read() or "[]")
except Exception:
  devices = []

for d in devices:
  if d.get("simulator"):
    continue
  plat = (d.get("platform") or "")
  if plat != "com.apple.platform.iphoneos":
    continue
  if d.get("ignored"):
    continue
  ident = (d.get("identifier") or "").strip()
  if ident:
    print(ident)
    break
PY
}

detect_device_id_system_profiler() {
  # Works even when CoreDevice is wedged, and often matches Xcode's device id.
  local serial
  serial="$(
    system_profiler SPUSBDataType 2>/dev/null \
      | awk '
        $1 ~ /^(iPhone|iPad):$/ {in_dev=1; next}
        in_dev && $1 == "Serial" && $2 == "Number:" {print $3; exit}
      ' \
      || true
  )"

  if [[ -z "${serial:-}" ]]; then
    return 1
  fi

  if [[ "$serial" == *"-"* ]]; then
    echo "$serial"
    return 0
  fi

  if (( ${#serial} > 8 )); then
    echo "${serial:0:8}-${serial:8}"
    return 0
  fi

  echo "$serial"
  return 0
}

maybe_cleanup_disk_space

USER_NAME="$(id -un)"
DEFAULT_BUNDLE_ID="com.smokesignal.${USER_NAME}"
BUNDLE_ID="${BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"

TEAM_ID="${TEAM_ID:-}"
if [[ -z "$TEAM_ID" ]]; then
  TEAM_ID="$(detect_team_id 2>/dev/null || true)"
fi
if [[ -z "$TEAM_ID" ]]; then
  cat <<EOF
Could not find an Xcode Team ID on this Mac.

Do this once:
1) Open Xcode
2) Xcode -> Settings -> Accounts
3) Sign in with your Apple ID (Personal Team is fine)
4) Quit Xcode

Then run this script again.
EOF
  exit 1
fi

DEVICE_ID="${DEVICE_ID:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(detect_device_id_xcdevice || true)"
fi
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(detect_device_id_system_profiler || true)"
fi
if [[ -z "$DEVICE_ID" ]]; then
  cat <<EOF
No iPhone detected.

Do this:
1) Plug your iPhone into your Mac with a cable
2) Unlock it
3) Tap "Trust" if prompted
4) Settings -> Privacy & Security -> Developer Mode (enable if prompted)

Then run this script again.
EOF
  exit 1
fi

echo "Building SmokeSignal for iPhone..."
echo "  DEVICE_ID: $DEVICE_ID"
echo "  TEAM_ID:   $TEAM_ID"
echo "  BUNDLE_ID: $BUNDLE_ID"

BUILD_LOG="$(mktemp /tmp/smokesignal-xcodebuild.XXXXXX.log)"
if ! xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  build 2>&1 | tee "$BUILD_LOG"; then
  if grep -q "is not installed. Please download and install the platform from Xcode > Settings > Components" "$BUILD_LOG"; then
    cat <<EOF

xcodebuild failed because the required iOS platform component is missing.

Fix (one-time):
1) Open Xcode
2) Xcode -> Settings -> Components
3) Download/install "iOS 26.2" (platform/device support)
4) Quit Xcode and re-run: ./run_on_iphone.sh

If the download won't start, make sure you're connected to the internet and reboot your Mac.
EOF
  else
    cat <<EOF

xcodebuild failed.

If the error says the device couldn't be found, Xcode can't see your iPhone as a run destination yet.

Fix:
1) Open Xcode -> Window -> Devices and Simulators
2) Select your iPhone and follow any prompts
3) Keep the iPhone unlocked, trusted, and Developer Mode enabled
4) Re-run: ./run_on_iphone.sh

If Xcode still can't see the phone, reboot your Mac and iPhone and try again.
EOF
  fi
  exit 1
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphoneos/SmokeSignal.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at: $APP_PATH"
  exit 1
fi

echo "Installing to iPhone..."
if ! xcrun devicectl device install app --timeout "$DEVICE_TIMEOUT" --device "$DEVICE_ID" "$APP_PATH"; then
  cat <<EOF
Install failed.

Next things to try:
1) Keep your iPhone unlocked on the home screen
2) Open Xcode -> Window -> Devices and Simulators and see if the phone appears
3) Re-run this script
EOF
  exit 1
fi

echo "Launching..."
xcrun devicectl device process launch --timeout "$DEVICE_TIMEOUT" --device "$DEVICE_ID" "$BUNDLE_ID" --terminate-existing --activate >/dev/null 2>&1 || true

echo "Done. If the app won't open, on iPhone go to Settings -> General -> VPN & Device Management and trust the developer certificate."
