#!/usr/bin/env bash
# Static checks for a built APK, used by CI and locally: TV launcher entries,
# banner, renderer flag, ABIs, SDK levels, permissions, signature and size.
#
# Usage: tool/check_apk.sh <apk> <max-size-MB> [expected ABIs]
#   expected ABIs: optional space-separated list that must match exactly,
#   e.g. "armeabi-v7a arm64-v8a" for the universal APK.
# Env:
#   ANDROID_HOME (or ANDROID_SDK_ROOT)  SDK with build-tools installed
#   BUILD_TOOLS_VERSION                  default 36.0.0
#   EXPECTED_CERT_SHA256                 optional signer SHA-256 (hex, colons allowed)
#   REQUIRE_RELEASE_SIGNED=1             fail if signed with the Android debug key
#   EXPECT_IMPELLER_OFF=1                require EnableImpeller=false (the -compat APK);
#                                        otherwise the APK must not override Impeller
set -euo pipefail

usage() {
  echo "usage: $0 <apk> <max-size-MB> [expected ABIs]" >&2
  exit 2
}

apk=${1:-}
max_mb=${2:-}
expected_abis=${3:-}
[[ -n "$apk" && -n "$max_mb" ]] || usage
[[ "$max_mb" =~ ^[0-9]+$ ]] || usage
[[ -f "$apk" ]] || { echo "error: no such APK: $apk" >&2; exit 2; }

sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
[[ -n "$sdk" ]] || { echo "error: set ANDROID_HOME" >&2; exit 2; }
build_tools="$sdk/build-tools/${BUILD_TOOLS_VERSION:-36.0.0}"
aapt2="$build_tools/aapt2"
apksigner="$build_tools/apksigner"
for tool in "$aapt2" "$apksigner"; do
  [[ -x "$tool" ]] || { echo "error: missing $tool" >&2; exit 2; }
done

allowed_abis=(armeabi-v7a arm64-v8a)
forbidden_permissions=(
  android.permission.CAMERA
  android.permission.RECORD_AUDIO
  android.permission.ACCESS_FINE_LOCATION
  android.permission.ACCESS_COARSE_LOCATION
  android.permission.ACCESS_BACKGROUND_LOCATION
)

failures=0
pass() { echo "  ok    $*"; }
fail() {
  echo "  FAIL  $*"
  failures=$((failures + 1))
}
# expect <description> <extended regex> <text>
expect() {
  if grep -Eq -- "$2" <<<"$3"; then pass "$1"; else fail "$1"; fi
}
# reject <description> <extended regex> <text>
reject() {
  if grep -Eq -- "$2" <<<"$3"; then fail "$1"; else pass "$1"; fi
}

echo "Checking $apk"
badging=$("$aapt2" dump badging "$apk")
manifest=$("$aapt2" dump xmltree --file AndroidManifest.xml "$apk")

echo "Launcher and TV:"
expect "launcher activity" "^launchable-activity: name='[^']+'" "$badging"
expect "leanback launcher activity" "^leanback-launchable-activity: name='[^']+'" "$badging"
expect "application banner" "^application: .*banner='[^']+'" "$badging"
expect "touchscreen not required" \
  "^[[:space:]]*uses-feature-not-required: name='android.hardware.touchscreen'" "$badging"
expect "leanback not required" \
  "^[[:space:]]*uses-feature-not-required: name='android.software.leanback'" "$badging"
reject "no required touchscreen" \
  "^[[:space:]]*uses-(implied-)?feature: name='android.hardware.touchscreen'" "$badging"
reject "no fixed screenOrientation" "screenOrientation" "$manifest"
expect "cleartext traffic allowed" "usesCleartextTraffic\([^)]*\)=(true|0xffffffff)" "$manifest"
expect "backup disabled" "allowBackup\([^)]*\)=(false|0x0)" "$manifest"
expect "predictive back enabled" "enableOnBackInvokedCallback\([^)]*\)=(true|0xffffffff)" "$manifest"

echo "Renderer:"
impeller=$(grep -A1 -F '"io.flutter.embedding.android.EnableImpeller"' <<<"$manifest" || true)
if [[ "${EXPECT_IMPELLER_OFF:-0}" == "1" ]]; then
  expect "Impeller off (EnableImpeller=false)" "android:value\([^)]*\)=(false|0x0)$" "$impeller"
else
  reject "no EnableImpeller override" "EnableImpeller" "$impeller"
fi

echo "SDK levels:"
expect "minSdk 24" "^(min)?[sS]dkVersion:'24'$" "$badging"
target_sdk=$(sed -nE "s/^targetSdkVersion:'([0-9]+)'.*/\1/p" <<<"$badging")
if [[ -n "$target_sdk" && "$target_sdk" -ge 35 ]]; then
  pass "targetSdk $target_sdk"
else
  fail "targetSdk ${target_sdk:-missing} (need >= 35)"
fi

echo "Permissions:"
expect "INTERNET" "^uses-permission: name='android.permission.INTERNET'" "$badging"
expect "ACCESS_NETWORK_STATE" \
  "^uses-permission: name='android.permission.ACCESS_NETWORK_STATE'" "$badging"
for permission in "${forbidden_permissions[@]}"; do
  reject "no ${permission##*.}" "^uses-permission: name='${permission//./\\.}'" "$badging"
done

echo "Native code:"
read -r -a abis <<<"$(sed -nE "s/^native-code: //p" <<<"$badging" | tr -d "'")"
if [[ ${#abis[@]} -eq 0 ]]; then
  fail "no native code found"
else
  for abi in "${abis[@]}"; do
    if [[ " ${allowed_abis[*]} " == *" $abi "* ]]; then
      pass "ABI $abi"
    else
      fail "unexpected ABI $abi (allowed: ${allowed_abis[*]})"
    fi
  done
fi
if [[ -n "$expected_abis" ]]; then
  have=$(printf '%s\n' "${abis[@]}" | sort | xargs)
  want=$(tr -s ' ' '\n' <<<"$expected_abis" | sort | xargs)
  if [[ "$have" == "$want" ]]; then pass "ABIs are exactly: $want"; else fail "ABIs [$have] != [$want]"; fi
fi

echo "Signature:"
if certs=$("$apksigner" verify --print-certs "$apk" 2>&1); then
  pass "apksigner verify"
  grep -E "certificate (DN|SHA-256 digest)" <<<"$certs" | sed 's/^/        /' || true
  digest=$(sed -nE 's/^Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]+)$/\1/p' <<<"$certs")
  if grep -q "CN=Android Debug" <<<"$certs"; then
    if [[ "${REQUIRE_RELEASE_SIGNED:-0}" == "1" ]]; then
      fail "signed with the Android debug key"
    else
      echo "  note  debug-signed: do not install over a release build"
    fi
  fi
  if [[ -n "${EXPECTED_CERT_SHA256:-}" ]]; then
    want=$(tr -d ': \n' <<<"$EXPECTED_CERT_SHA256" | tr '[:upper:]' '[:lower:]')
    have=$(tr '[:upper:]' '[:lower:]' <<<"$digest")
    if [[ "$have" == "$want" ]]; then pass "certificate matches"; else fail "certificate $digest != $want"; fi
  fi
else
  fail "apksigner verify"
  # shellcheck disable=SC2001
  sed 's/^/        /' <<<"$certs"
fi

echo "Size:"
bytes=$(wc -c <"$apk" | tr -d ' ')
size_mb=$(awk -v b="$bytes" 'BEGIN { printf "%.1f", b / 1048576 }')
if ((bytes <= max_mb * 1024 * 1024)); then
  pass "$size_mb MB <= $max_mb MB"
else
  fail "$size_mb MB > $max_mb MB"
fi

if ((failures > 0)); then
  echo "$failures check(s) failed for $apk" >&2
  exit 1
fi
echo "All checks passed for $apk"
