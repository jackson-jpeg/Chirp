#!/bin/bash
# Runs the App Review compliance UI tests on the Mac, on the iPad the reviewer
# used and on an iPhone.
#
# Why it exists: every one of these tests depends on a permission that can only
# be answered once per install, so each test needs its own fresh app and its own
# fresh privacy state. `xcodebuild test` with several tests in one run cannot do
# that, so this drives one test at a time: uninstall, reset privacy, run.
#
# Runs on the MAC (over macbook-tunnel). The VPS cannot run these tools.
#
# Usage: bash run-review-tests.sh [--build-only] [--iphone-only] [--test NAME]
set -uo pipefail

# Non-interactive ssh gets a bare PATH; the toolchain lives in Homebrew.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

REPO="$HOME/Chirp"
SCHEME="ChirpDeviceTests"
BUNDLE_ID="com.jacksonmsanger.chirpchirp"
RUNTIME_MATCH="iOS 26"
IPAD_NAME="Chirp-iPad-Air-11-M3"
OUT="/tmp/chirp-review-tests"
DD="$HOME/Library/Developer/Xcode/DerivedData/chirp-review-tests"

TESTS=(
  "ReviewComplianceTests/testOnboardingMicrophonePromptThenDenyKeepsAppUsable"
  "ReviewComplianceTests/testOnboardingMicrophonePromptThenAllow"
  "ReviewComplianceTests/testLocationExplainerOnlyLeadsToThePrompt"
  "ReviewComplianceTests/testDemoModeGivesASingleDeviceEverything"
  "ReviewComplianceTests/testEmptyStateOffersDemoMode"
)

BUILD_ONLY=false
IPHONE_ONLY=false
ONE_TEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --build-only) BUILD_ONLY=true; shift ;;
    --iphone-only) IPHONE_ONLY=true; shift ;;
    --test) ONE_TEST="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -n "$ONE_TEST" ]; then
  # --test takes one name or a comma-separated list.
  TESTS=()
  IFS=',' read -ra NAMES <<< "$ONE_TEST"
  for n in "${NAMES[@]}"; do TESTS+=("ReviewComplianceTests/$n"); done
fi

SIMCTL="$(xcode-select -p)/usr/bin/simctl"
XCB="$(xcode-select -p)/usr/bin/xcodebuild"
XCRESULT="$(xcode-select -p)/usr/bin/xcresulttool"

cd "$REPO" || exit 1
mkdir -p "$OUT"

echo "== disk before =="
df -h / | tail -1

# The Mac is tight on space: this run's DerivedData is its own tree, removed
# up front, and the shared one goes too so a stale archive does not fill the
# disk mid-run.
rm -rf "$DD"
rm -rf "$HOME/Library/Developer/Xcode/DerivedData/ChirpChirp-"*

command -v xcodegen >/dev/null || { echo "FATAL: xcodegen missing"; exit 1; }
xcodegen generate >/dev/null || { echo "FATAL: project generation failed"; exit 1; }

# --- simulators ---------------------------------------------------------

runtime_id() {
  "$SIMCTL" list runtimes | grep "$RUNTIME_MATCH" | tail -1 | awk '{print $NF}'
}

device_udid() {  # $1 = device name
  "$SIMCTL" list devices available | grep -F "$1 (" | head -1 |
    sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

RT="$(runtime_id)"
[ -z "$RT" ] && { echo "FATAL: no $RUNTIME_MATCH runtime installed"; exit 1; }
echo "runtime: $RT"

IPAD_UDID="$(device_udid "$IPAD_NAME")"
if [ -z "$IPAD_UDID" ]; then
  TYPE="$("$SIMCTL" list devicetypes | grep -i "iPad Air 11-inch (M3)" | head -1 |
          sed -E 's/.*\((com\.apple[^)]*)\)/\1/')"
  if [ -z "$TYPE" ]; then
    echo "FATAL: this Xcode has no iPad Air 11-inch (M3) device type"
    "$SIMCTL" list devicetypes | grep -i "iPad Air"
    exit 1
  fi
  echo "creating $IPAD_NAME ($TYPE)"
  IPAD_UDID="$("$SIMCTL" create "$IPAD_NAME" "$TYPE" "$RT")" || exit 1
fi
echo "iPad:   $IPAD_UDID"

IPHONE_UDID="$(device_udid "iPhone 16 Pro Max")"
[ -z "$IPHONE_UDID" ] && IPHONE_UDID="$(device_udid "iPhone 16")"
[ -z "$IPHONE_UDID" ] && { echo "FATAL: no iPhone simulator"; exit 1; }
echo "iPhone: $IPHONE_UDID"

DEVICES=("iphone:$IPHONE_UDID")
$IPHONE_ONLY || DEVICES=("ipad:$IPAD_UDID" "iphone:$IPHONE_UDID")

for entry in "${DEVICES[@]}"; do
  "$SIMCTL" boot "${entry#*:}" 2>/dev/null
done

# --- build once ---------------------------------------------------------

echo "== build-for-testing =="
BUILD_LOG="$OUT/build.log"
"$XCB" build-for-testing \
  -scheme "$SCHEME" \
  -destination "id=$IPHONE_UDID" \
  -derivedDataPath "$DD" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  PROVISIONING_PROFILE_SPECIFIER="" CODE_SIGN_STYLE=Automatic \
  >"$BUILD_LOG" 2>&1
RC=$?
if [ $RC -ne 0 ]; then
  echo "BUILD FAILED (rc=$RC). Errors:"
  grep -E "error:" "$BUILD_LOG" | head -30
  exit $RC
fi
echo "build ok"
$BUILD_ONLY && exit 0

# --- run, one test per fresh install ------------------------------------

PASS=0
FAIL=0
FAILED_NAMES=""

for entry in "${DEVICES[@]}"; do
  label="${entry%%:*}"
  udid="${entry#*:}"
  for t in "${TESTS[@]}"; do
    name="${t##*/}"
    tag="$label-$name"
    echo "== $tag =="

    # Erase the whole device, not just the app: an uninstall was observed to
    # leave the app's defaults behind (the app came up already onboarded, with
    # a callsign from a previous run), which would quietly skip the very
    # onboarding screens under test. Erase is the only state this can trust.
    "$SIMCTL" shutdown "$udid" >/dev/null 2>&1
    "$SIMCTL" erase "$udid" >/dev/null 2>&1
    "$SIMCTL" boot "$udid" >/dev/null 2>&1
    "$SIMCTL" bootstatus "$udid" -b >/dev/null 2>&1

    # The microphone tests need the prompt to be unanswered; every other test
    # needs push-to-talk to work, which on an erased device means granting it
    # here rather than leaving the press to raise a prompt mid-test.
    case "$name" in
      *Microphone*) ;;
      *) "$SIMCTL" privacy "$udid" grant microphone "$BUNDLE_ID" >/dev/null 2>&1 ;;
    esac
    rm -rf "$OUT/$tag.xcresult"

    "$XCB" test \
      -scheme "$SCHEME" \
      -destination "id=$udid" \
      -derivedDataPath "$DD" \
      -resultBundlePath "$OUT/$tag.xcresult" \
      -only-testing:"ChirpUITests/$t" \
      CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
      >"$OUT/$tag.log" 2>&1
    rc=$?

    # Trust the artifacts, not the log text: a result bundle plus xcodebuild's
    # own exit code, and a count that proves a test actually ran.
    ran=$(grep -cE "Test Case '.*' (passed|failed)" "$OUT/$tag.log")
    if [ "$rc" -eq 0 ] && [ -d "$OUT/$tag.xcresult" ] && [ "$ran" -ge 1 ]; then
      echo "RESULT $tag PASS"
      PASS=$((PASS + 1))
    else
      echo "RESULT $tag FAIL (rc=$rc, cases=$ran)"
      grep -E "error:|XCTAssert|Assertion Failure|failed -" "$OUT/$tag.log" | head -12
      FAIL=$((FAIL + 1))
      FAILED_NAMES="$FAILED_NAMES $tag"
    fi
  done
done

# --- screenshots --------------------------------------------------------

STAMP="$(date +%Y%m%d-%H%M)"
SHOTS="$HOME/Downloads/chirpchirp-shots-$STAMP"
mkdir -p "$SHOTS"
for bundle in "$OUT"/*.xcresult; do
  [ -d "$bundle" ] || continue
  tag="$(basename "$bundle" .xcresult)"
  dir="$SHOTS/$tag"
  mkdir -p "$dir"
  "$XCRESULT" export attachments --path "$bundle" --output-path "$dir" >/dev/null 2>&1
  # Exported attachments are named by UUID; manifest.json carries the names the
  # tests gave them, which is what the report has to reference.
  python3 - "$dir" <<'PY'
import json, os, sys
d = sys.argv[1]
manifest = os.path.join(d, "manifest.json")
if not os.path.exists(manifest):
    raise SystemExit(0)
for entry in json.load(open(manifest)):
    for att in entry.get("attachments", []):
        src = os.path.join(d, att.get("exportedFileName", ""))
        name = att.get("suggestedHumanReadableName") or att.get("name") or ""
        if not name or not os.path.exists(src):
            continue
        root, ext = os.path.splitext(src)
        safe = "".join(c if c.isalnum() or c in "-_." else "-" for c in name)
        if not safe.endswith(ext):
            safe += ext
        dst = os.path.join(d, safe)
        n = 2
        while os.path.exists(dst):
            dst = os.path.join(d, f"{os.path.splitext(safe)[0]}-{n}{ext}")
            n += 1
        os.rename(src, dst)
PY
done
find "$SHOTS" -name "*.png" | wc -l | xargs echo "screenshots exported:"
echo "SHOTS_DIR $SHOTS"

echo "== disk after =="
df -h / | tail -1
echo "SUMMARY pass=$PASS fail=$FAIL failed:$FAILED_NAMES"
[ "$FAIL" -eq 0 ] || exit 1
