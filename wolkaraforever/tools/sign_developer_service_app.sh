#!/bin/bash
# Sign a generic, unsigned Developer-service Tolkara.app with the builder's own
# Apple Development identity and the two provisioning profiles it needs.
#
# usage:
#   wolkaraforever/tools/sign_developer_service_app.sh \
#       --app Tolkara.app \
#       --app-profile app.mobileprovision \
#       --tunnel-profile tunnel.mobileprovision \
#       --team TEAMID --bundle-id BUNDLE --keychain-group GROUP \
#       [--identity "Apple Development"] \
#       [--output out.ipa] [--report out.txt] [--revision SHA]
#
# This is the signing half of the GitHub runner build: the runner compiles with
# CODE_SIGNING_ALLOWED=NO, then this signs nested code in the only order iOS
# accepts (all dylibs and frameworks, then the extension, then the app), embeds
# each profile, and runs verify_developer_service_ipa.sh. It runs on macOS
# because codesign and security are Apple's tools.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
app=""
app_profile=""
tunnel_profile=""
team=${DEVELOPMENT_TEAM:-}
bundle=${TOLKARA_BUNDLE_ID:-}
group=${TOLKARA_KEYCHAIN_GROUP:-}
identity_filter=${SIGN_IDENTITY:-Apple Development}
output="WolkaraForever-developer-service.ipa"
report=""
revision=${TOLKARA_SOURCE_REVISION:-}

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

die() { echo "sign_developer_service_app: $*" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --app) app=${2:-}; shift 2;;
        --app-profile) app_profile=${2:-}; shift 2;;
        --tunnel-profile) tunnel_profile=${2:-}; shift 2;;
        --team) team=${2:-}; shift 2;;
        --bundle-id) bundle=${2:-}; shift 2;;
        --keychain-group) group=${2:-}; shift 2;;
        --identity) identity_filter=${2:-}; shift 2;;
        --output) output=${2:-}; shift 2;;
        --report) report=${2:-}; shift 2;;
        --revision) revision=${2:-}; shift 2;;
        -h|--help) usage; exit 0;;
        *) die "unknown argument: $1";;
    esac
done

[ -n "$app" ] || die "--app is required"
[ -d "$app" ] || die "the app does not exist: $app"
[ -n "$app_profile" ] && [ -f "$app_profile" ] || die "--app-profile must name a .mobileprovision file"
[ -n "$tunnel_profile" ] && [ -f "$tunnel_profile" ] || die "--tunnel-profile must name a .mobileprovision file"
[ -n "$team" ] || die "--team (or DEVELOPMENT_TEAM) is required"
[ -n "$bundle" ] || die "--bundle-id (or TOLKARA_BUNDLE_ID) is required"
[ -n "$group" ] || die "--keychain-group (or TOLKARA_KEYCHAIN_GROUP) is required"

case "$app" in /*) ;; *) app="$PWD/$app";; esac
case "$app_profile" in /*) ;; *) app_profile="$PWD/$app_profile";; esac
case "$tunnel_profile" in /*) ;; *) tunnel_profile="$PWD/$tunnel_profile";; esac
case "$output" in /*) ;; *) output="$PWD/$output";; esac
if [ -z "$report" ]; then
    report="${output%.ipa}.verification.txt"
elif [ "${report#/}" = "$report" ]; then
    report="$PWD/$report"
fi

case "$group" in
    "$team."*) group_value=$group;;
    *) group_value="$team.$group";;
esac

tmp=$(mktemp -d "${TMPDIR:-/tmp}/wolkaraforever-sign.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

field() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }
set_field() {
    local plist=$1 key=$2 value=$3
    if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" >/dev/null
    else
        /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist" >/dev/null
    fi
}

# The unsigned build must have been made for exactly these identifiers; catching
# a mismatch here is much clearer than a profile failure later.
actual_bundle=$(field "$app/Info.plist" CFBundleIdentifier)
[ "$actual_bundle" = "$bundle" ] || {
    die "the app was built as $actual_bundle; rebuild with TOLKARA_BUNDLE_ID=$bundle"
}
mode=$(field "$app/Info.plist" TolkaraPreselectedExecutionMode)
[ "$mode" = developer-service ] || {
    die "the app's execution mode is '$mode'; rebuild with TOLKARA_MODE=developer-service"
}
runtime=$(field "$app/Info.plist" TolkaraGuestRuntime)
[ "$runtime" = emulated ] || die "the app's guest runtime is '$runtime', expected emulated"

appex="$app/PlugIns/LocalAuthorizationTunnel.appex"
[ -d "$appex" ] || die "the app does not carry LocalAuthorizationTunnel.appex"
actual_appex=$(field "$appex/Info.plist" CFBundleIdentifier)
[ "$actual_appex" = "$bundle.authorization" ] || {
    die "the extension was built as $actual_appex; expected $bundle.authorization"
}

# Decode and validate both profiles first: a bad profile must stop the build
# before any code is signed.
security cms -D -i "$app_profile" > "$tmp/app-profile.plist" || die "cannot read the app profile"
security cms -D -i "$tunnel_profile" > "$tmp/tunnel-profile.plist" || die "cannot read the tunnel profile"
python3 "$script_dir/signing_profile.py" inspect \
    --profile-plist "$tmp/app-profile.plist" --kind app --team "$team" \
    --bundle "$bundle" --keychain-group "$group" \
    --entitlements-out "$tmp/app.entitlements" \
    || die "the app profile is not usable for $bundle"
python3 "$script_dir/signing_profile.py" inspect \
    --profile-plist "$tmp/tunnel-profile.plist" --kind tunnel --team "$team" \
    --bundle "$bundle" --keychain-group "$group" \
    --entitlements-out "$tmp/tunnel.entitlements" \
    || die "the tunnel profile is not usable for $bundle.authorization"

# Resolve the requested identity to a full Apple Development name for this team.
signing_identity=$(
    security find-identity -v -p codesigning |
        grep -F "($team)" | grep -F "$identity_filter" | head -1 |
        sed -n 's/.*"\(.*\)".*/\1/p'
) || true
if [ -z "$signing_identity" ]; then
    signing_identity=$(
        security find-identity -v -p codesigning |
            grep -F "($team)" | head -1 |
            sed -n 's/.*"\(.*\)".*/\1/p'
    ) || true
fi
[ -n "$signing_identity" ] || {
    echo "sign_developer_service_app: available code-signing identities:" >&2
    security find-identity -v -p codesigning >&2 || true
    die "no code-signing identity for team $team (expected an Apple Development certificate)"
}
echo "sign_developer_service_app: signing with '$signing_identity'"

# The app and extension read this key from Info.plist at runtime. Xcode normally
# substitutes $(AppIdentifierPrefix) during signing; an unsigned build cannot, so
# set the resolved group explicitly before the seal is made.
set_field "$appex/Info.plist" TKPairingKeychainGroup "$group_value"
set_field "$app/Info.plist" TKPairingKeychainGroup "$group_value"

# Sign every nested Mach-O first. Signing the outer bundle before its contents
# would seal an unsigned inner binary and iOS would refuse it.
find "$app" -type f \( -name '*.dylib' -o -name '*.so' \) -print | while IFS= read -r item; do
    codesign --force --sign "$signing_identity" --timestamp=none "$item" >/dev/null
done
find "$app" -type d -name '*.framework' -print | while IFS= read -r item; do
    codesign --force --sign "$signing_identity" --timestamp=none "$item" >/dev/null
done

cp "$tunnel_profile" "$appex/embedded.mobileprovision"
codesign --force --sign "$signing_identity" \
    --entitlements "$tmp/tunnel.entitlements" \
    --generate-entitlement-der --timestamp=none "$appex" >/dev/null

cp "$app_profile" "$app/embedded.mobileprovision"
codesign --force --sign "$signing_identity" \
    --entitlements "$tmp/app.entitlements" \
    --generate-entitlement-der --timestamp=none "$app" >/dev/null

mkdir -p "$(dirname "$output")"
rm -rf "$tmp/Payload"
mkdir -p "$tmp/Payload"
ditto --norsrc --noextattr "$app" "$tmp/Payload/Tolkara.app"
rm -f "$output"
( cd "$tmp" && zip -qry "$output" Payload )
unzip -tqq "$output" || die "the packaged .ipa is not readable"

verifier="$script_dir/verify_developer_service_ipa.sh"
[ -x "$verifier" ] || die "verify_developer_service_ipa.sh is missing next to this script"
TOLKARA_BUNDLE_ID=$bundle DEVELOPMENT_TEAM=$team TOLKARA_KEYCHAIN_GROUP=$group \
TOLKARA_SOURCE_REVISION=$revision TOLKARA_SOURCE_REF=${TOLKARA_SOURCE_REF:-} \
    "$verifier" "$output" "$report" || die "the signed .ipa did not verify"

echo "sign_developer_service_app: PASS - $output"
echo "sign_developer_service_app: report - $report"
