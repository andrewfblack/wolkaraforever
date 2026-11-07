#!/bin/bash
# Verify a signed Developer-service WolkaraForever .ipa before it is installed.
#
# usage: wolkaraforever/tools/verify_developer_service_ipa.sh <ipa> [report]
#
# This is the integrated Tolkara target, not the unsigned TolkaraDiagnostics
# External-JIT IPA that verify_ipa.sh checks. It requires the app extension and
# the two development profiles, and it proves the signature, team, bundle IDs,
# execution mode and capabilities that Developer service needs.
#
# Settings come from the environment (TOLKARA_BUNDLE_ID, DEVELOPMENT_TEAM,
# TOLKARA_KEYCHAIN_GROUP) or from the flags below. The runner and the Mac
# install helper both set them from the same values used to build.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2

ipa=${1:-}
report=${2:-}
[ -n "$ipa" ] && [ -f "$ipa" ] || {
    echo "usage: wolkaraforever/tools/verify_developer_service_ipa.sh <ipa> [report]" >&2
    exit 2
}
[ "$#" -le 2 ] || { echo "verify_developer_service_ipa: too many arguments" >&2; exit 2; }
case "$ipa" in /*) ;; *) ipa="$PWD/$ipa";; esac
if [ -z "$report" ]; then
    report="${ipa%.ipa}.verification.txt"
elif [ "${report#/}" = "$report" ]; then
    report="$PWD/$report"
fi

bundle=${TOLKARA_BUNDLE_ID:-}
team=${DEVELOPMENT_TEAM:-}
group=${TOLKARA_KEYCHAIN_GROUP:-}
revision=${TOLKARA_SOURCE_REVISION:-}
source_ref=${TOLKARA_SOURCE_REF:-}

fail() { echo "verify_developer_service_ipa: $*" >&2; exit 1; }
field() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/wolkaraforever-verify.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

unzip -tqq "$ipa" || fail "the file is not a readable .ipa"
unzip -qq "$ipa" -d "$tmp"

apps=$(find "$tmp/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' | wc -l | tr -d ' ')
[ "$apps" = 1 ] || fail "expected exactly one app under Payload, found $apps"
app=$(find "$tmp/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' | head -1)
[ "$(basename "$app")" = "Tolkara.app" ] || fail "the app is $(basename "$app"), not Tolkara.app"
appex="$app/PlugIns/LocalAuthorizationTunnel.appex"
[ -d "$appex" ] || fail "the app does not carry LocalAuthorizationTunnel.appex"

app_id=$(field "$app/Info.plist" CFBundleIdentifier)
[ -n "$bundle" ] || bundle=$app_id
[ "$app_id" = "$bundle" ] || fail "the app is $app_id, expected $bundle"

mode=$(field "$app/Info.plist" TolkaraPreselectedExecutionMode)
[ "$mode" = developer-service ] || fail "execution mode is '$mode', expected developer-service"
runtime=$(field "$app/Info.plist" TolkaraGuestRuntime)
[ "$runtime" = emulated ] || fail "guest runtime is '$runtime', expected emulated"

appex_id=$(field "$appex/Info.plist" CFBundleIdentifier)
[ "$appex_id" = "$bundle.authorization" ] || {
    fail "the extension is $appex_id, expected $bundle.authorization"
}

[ -f "$app/embedded.mobileprovision" ] || fail "the app has no embedded.mobileprovision"
[ -f "$appex/embedded.mobileprovision" ] || fail "the extension has no embedded.mobileprovision"

# The signed team is the profile's team. If the caller did not set it, take it from
# the app's signature so a human can still inspect an artifact by hand.
if [ -z "$team" ]; then
    team=$(codesign -dvv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)
fi
[ -n "$team" ] || fail "cannot determine the signing team"
case "$team" in
    "not set"|"") fail "the app is not signed with a development team";;
esac

# The Keychain group has to be the same one the app and extension read. If the
# caller did not give it, take it from the app's own Info.plist.
if [ -z "$group" ]; then
    pairing=$(field "$app/Info.plist" TKPairingKeychainGroup)
    case "$pairing" in
        "$team."*) group=${pairing#"$team."};;
        *) group=$pairing;;
    esac
fi
[ -n "$group" ] || fail "cannot determine the Keychain group"

# Both embedded profiles must be development profiles for these exact bundles,
# still valid, and carry the capabilities this build needs.
security cms -D -i "$app/embedded.mobileprovision" > "$tmp/app-profile.plist" \
    || fail "cannot read the app's embedded profile"
security cms -D -i "$appex/embedded.mobileprovision" > "$tmp/tunnel-profile.plist" \
    || fail "cannot read the extension's embedded profile"

app_profile=$(python3 wolkaraforever/tools/signing_profile.py inspect \
    --profile-plist "$tmp/app-profile.plist" --kind app --team "$team" \
    --bundle "$bundle" --keychain-group "${group:-}" \
    --entitlements-out "$tmp/app-profile.entitlements" | sed -n '1p') \
    || fail "the app's embedded profile is not usable for $bundle"
tunnel_profile=$(python3 wolkaraforever/tools/signing_profile.py inspect \
    --profile-plist "$tmp/tunnel-profile.plist" --kind tunnel --team "$team" \
    --bundle "$bundle" --keychain-group "${group:-}" \
    --entitlements-out "$tmp/tunnel-profile.entitlements" | sed -n '1p') \
    || fail "the extension's embedded profile is not usable for $bundle.authorization"

# The profile's Keychain group is the authority. Require the app's Info.plist to
# name the same group, because that is what the app and extension read at runtime.
expected_group=$(python3 - "$team" "${group:-}" <<'PY'
import sys
team, group = sys.argv[1], sys.argv[2].strip()
prefix = team + "."
if group.startswith(prefix):
    group = group[len(prefix):]
if not group:
    raise SystemExit("empty Keychain group")
print(team + "." + group)
PY
) || fail "TOLKARA_KEYCHAIN_GROUP is empty"
for target in "$app" "$appex"; do
    actual=$(field "$target/Info.plist" TKPairingKeychainGroup)
    [ "$actual" = "$expected_group" ] || {
        fail "$(basename "$target") names Keychain group '$actual', expected '$expected_group'"
    }
done

# Signatures, identifiers and entitlements, deepest first.
verify_signed() { # path expected-identifier kind
    local path=$1 identifier=$2 kind=$3 signature
    codesign --verify --deep --strict --verbose=2 "$path" > "$tmp/signature.log" 2>&1 || {
        cat "$tmp/signature.log" >&2
        fail "$(basename "$path") does not pass signature verification"
    }
    signature=$(codesign -dvv "$path" 2>&1) || fail "$(basename "$path") is not signed"
    printf '%s\n' "$signature" | grep -qx "Identifier=$identifier" ||
        fail "$(basename "$path") is signed as '$(printf '%s\n' "$signature" | sed -n 's/^Identifier=//p' | head -1)', expected $identifier"
    printf '%s\n' "$signature" | grep -qx "TeamIdentifier=$team" ||
        fail "$(basename "$path") is not signed by team $team"
    printf '%s\n' "$signature" | grep -q '^Authority=Apple Development:' ||
        fail "$(basename "$path") must use an Apple Development certificate"
    codesign -d --entitlements :- "$path" > "$tmp/$kind.entitlements" 2>/dev/null ||
        fail "$(basename "$path") has no readable entitlements"
    if ! python3 - "$tmp/$kind.entitlements" "$team" "$identifier" "$expected_group" "$kind" <<'PY'
import plistlib, sys
path, team, identifier, group, kind = sys.argv[1:]
with open(path, "rb") as source:
    entitlements = plistlib.load(source)
if entitlements.get("application-identifier") != team + "." + identifier:
    raise SystemExit("application-identifier mismatch")
if entitlements.get("com.apple.developer.team-identifier") not in (None, team):
    raise SystemExit("team mismatch")
groups = entitlements.get("keychain-access-groups") or []
if group not in groups and team + ".*" not in groups:
    raise SystemExit("Keychain group missing")
extensions = entitlements.get("com.apple.developer.networking.networkextension") or []
if "packet-tunnel-provider" not in extensions:
    raise SystemExit("packet tunnel missing")
if kind == "app":
    for capability in ("com.apple.developer.kernel.increased-memory-limit",
                       "com.apple.developer.kernel.extended-virtual-addressing"):
        if entitlements.get(capability) is not True:
            raise SystemExit("missing " + capability)
PY
    then
        fail "$(basename "$path") does not carry the Developer-service entitlements"
    fi
}
verify_signed "$appex" "$bundle.authorization" tunnel
verify_signed "$app" "$bundle" app

sha=$(shasum -a 256 "$ipa" | awk '{print $1}')
[ -n "$revision" ] || revision=$(git rev-parse HEAD 2>/dev/null || echo unknown)
mkdir -p "$(dirname "$report")"
{
    echo "IPA: $ipa"
    echo "SHA256: $sha"
    echo "Source revision: $revision"
    [ -z "$source_ref" ] || echo "Source ref: $source_ref"
    echo "Bundle: Tolkara.app"
    echo "Bundle identifier: $bundle"
    echo "Execution mode: $mode"
    echo "Guest runtime: $runtime"
    echo "Signing team: $team"
    echo "App extension: LocalAuthorizationTunnel.appex ($bundle.authorization)"
    echo "App profile: ${app_profile#signing_profile: OK - }"
    echo "Tunnel profile: ${tunnel_profile#signing_profile: OK - }"
    echo "Entitlements: increased-memory-limit, extended-virtual-addressing, networkextension(packet-tunnel-provider)"
    echo "Keychain group: $expected_group"
} > "$report"
echo "verify_developer_service_ipa: PASS ($report)"
