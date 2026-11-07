#!/bin/bash
# Export the Mac's Apple Development certificate and the two provisioning
# profiles into the fork's GitHub Actions secrets and variables.
#
# Run this on the Mac after one successful local build/install: that build
# registers the iPad, creates the App IDs and capabilities, and puts the
# profiles in Xcode's profile directory. This script never prints private key
# material and never writes it anywhere except GitHub's encrypted secrets.
#
# usage:
#   wolkaraforever/tools/ci_signing_material.sh --cert ~/Downloads/AppleDevelopment.p12
#
# flags:
#   --cert PATH            .p12 exported from Keychain Access (certificate + private key)
#   --cert-password TEXT   its password; otherwise prompted
#   --app-profile PATH     use this app profile instead of searching Xcode's directory
#   --tunnel-profile PATH  use this extension profile instead of searching
#   --device UDID          require the profiles to include this iPad (default: DEVICE)
#   --repo OWNER/REPO      default: the 'fork' remote, else 'origin'
#   --no-upload            validate and print only; change nothing on GitHub
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=wolkaraforever/tools/env.sh
. wolkaraforever/tools/env.sh
TOOLS=$ROOT/wolkaraforever/tools

cert=""
cert_password=""
app_profile=""
tunnel_profile=""
device=${DEVICE:-}
repo=""
upload=1

die() { echo "ci_signing_material: $*" >&2; exit 2; }

usage() {
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --cert) cert=${2:-}; shift 2;;
        --cert-password) cert_password=${2:-}; shift 2;;
        --app-profile) app_profile=${2:-}; shift 2;;
        --tunnel-profile) tunnel_profile=${2:-}; shift 2;;
        --device) device=${2:-}; shift 2;;
        --repo) repo=${2:-}; shift 2;;
        --no-upload) upload=0; shift;;
        -h|--help) usage; exit 0;;
        *) die "unknown argument: $1";;
    esac
done

[ "$(uname -s)" = Darwin ] || die "this must run on the Mac that has Xcode"
[ -n "${DEVELOPMENT_TEAM:-}" ] || die "DEVELOPMENT_TEAM is not set in local.env"
[ -n "${TOLKARA_BUNDLE_ID:-}" ] || die "TOLKARA_BUNDLE_ID is not set in local.env"
[ -n "${TOLKARA_KEYCHAIN_GROUP:-}" ] || die "TOLKARA_KEYCHAIN_GROUP is not set in local.env"
command -v security >/dev/null || die "security is missing"
command -v python3 >/dev/null || die "python3 is missing"
[ "$upload" = 0 ] || command -v gh >/dev/null || die "gh is missing; install it with 'brew install gh' and run 'gh auth login'"

if [ -z "$repo" ]; then
    url=$(git remote get-url fork 2>/dev/null || git remote get-url origin 2>/dev/null || true)
    [ -n "$url" ] || die "no git remote; pass --repo OWNER/REPO"
    repo=$(printf '%s' "$url" | sed -E 's#.*github\.com[:/]##; s#\.git$##')
fi
case "$repo" in
    */*) ;;
    *) die "--repo must be OWNER/REPO, got '$repo'";;
esac

tmp=$(mktemp -d "${TMPDIR:-/tmp}/wolkaraforever-ci-signing.XXXXXX")
check_keychain=""
trap 'security delete-keychain "${check_keychain:-}" 2>/dev/null || true; rm -rf "$tmp"' EXIT

profile_dirs=(
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
    "$HOME/Library/MobileDevice/Provisioning Profiles"
)

inspect_json() { # profile-file kind
    local plist=$1 kind=$2
    security cms -D -i "$plist" > "$tmp/profile.plist" 2>/dev/null || return 1
    local args=()
    [ -z "$device" ] || args=(--device "$device")
    python3 "$TOOLS/signing_profile.py" inspect \
        --profile-plist "$tmp/profile.plist" --kind "$kind" \
        --team "$DEVELOPMENT_TEAM" --bundle "$TOLKARA_BUNDLE_ID" \
        --keychain-group "$TOLKARA_KEYCHAIN_GROUP" \
        "${args[@]}" --json
}

find_profile() { # kind
    local kind=$1 best_epoch="" best_path="" epoch out_json path dir errorlog
    errorlog="$tmp/$kind-errors.log"
    : > "$errorlog"
    for dir in "${profile_dirs[@]}"; do
        [ -d "$dir" ] || continue
        for path in "$dir"/*.mobileprovision; do
            [ -f "$path" ] || continue
            if out_json=$(inspect_json "$path" "$kind" 2>>"$errorlog"); then
                epoch=$(printf '%s' "$out_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["expires_epoch"])')
                if [ -z "$best_epoch" ] || [ "$epoch" -gt "$best_epoch" ]; then
                    best_epoch=$epoch
                    best_path=$path
                    printf '%s\n' "$out_json" > "$tmp/$kind.json"
                fi
            fi
        done
    done
    if [ -z "$best_path" ]; then
        echo "ci_signing_material: no usable $kind profile for $DEVELOPMENT_TEAM.$TOLKARA_BUNDLE_ID in:" >&2
        printf '  %s\n' "${profile_dirs[@]}" >&2
        echo "A development profile must include this iPad, the Network Extension (packet tunnel)," >&2
        echo "and (for the app) Increased Memory Limit, Extended Virtual Addressing and the" >&2
        echo "Keychain group $DEVELOPMENT_TEAM.$TOLKARA_KEYCHAIN_GROUP." >&2
        echo "Run one successful local build/install first, or create the profiles at" >&2
        echo "developer.apple.com and download them into Xcode's profile directory." >&2
        if [ -s "$errorlog" ]; then
            echo "Reasons seen:" >&2
            tail -10 "$errorlog" | sed 's/^/  /' >&2
        fi
        exit 1
    fi
    printf '%s\n' "$best_path" > "$tmp/$kind.path"
}

if [ -n "$app_profile" ]; then
    inspect_json "$app_profile" app > "$tmp/app.json" || die "$app_profile is not a usable app profile"
    printf '%s\n' "$app_profile" > "$tmp/app.path"
else
    find_profile app
fi
if [ -n "$tunnel_profile" ]; then
    inspect_json "$tunnel_profile" tunnel > "$tmp/tunnel.json" || die "$tunnel_profile is not a usable tunnel profile"
    printf '%s\n' "$tunnel_profile" > "$tmp/tunnel.path"
else
    find_profile tunnel
fi
app_profile=$(cat "$tmp/app.path")
tunnel_profile=$(cat "$tmp/tunnel.path")

profile_summary() { # kind
    local kind=$1 json
    json=$(cat "$tmp/$kind.json")
    printf '%s' "$json" | python3 -c '
import json, sys
value = json.load(sys.stdin)
print("%s (%s), %d device(s), expires %s" % (
    value["name"] or "unnamed", value["uuid"] or "no UUID",
    value["devices"], value["expires"]))'
}

if [ "$upload" = 1 ] && [ -z "$cert" ]; then
    cat >&2 <<'MESSAGE'
ci_signing_material: --cert is required to upload.

Export the Apple Development certificate from Keychain Access:
  1. Open Keychain Access > login > My Certificates.
  2. Select "Apple Development: <name> (<TEAM>)" together with its private key.
  3. Right-click > Export... > Personal Information Exchange (.p12), set a password.
  4. Run this again with --cert ~/Downloads/AppleDevelopment.p12

The private key goes only into GitHub's encrypted Actions secrets.
MESSAGE
    exit 2
fi

certificate_identity=""
if [ -n "$cert" ]; then
    [ -f "$cert" ] || die "certificate not found: $cert"
    if [ -z "$cert_password" ]; then
        [ -t 0 ] || die "--cert-password is required when not running interactively"
        printf 'Password for %s: ' "$cert" >&2
        stty -echo
        IFS= read -r cert_password
        stty echo
        echo >&2
    fi
    check_keychain="$tmp/check.keychain-db"
    keychain_password=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
    security create-keychain -p "$keychain_password" "$check_keychain" >/dev/null
    security unlock-keychain -p "$keychain_password" "$check_keychain" >/dev/null
    security import "$cert" -k "$check_keychain" -P "$cert_password" \
        -T /usr/bin/codesign >/dev/null 2>&1 ||
        die "cannot import $cert (is the password right, and does it contain the private key?)"
    identities=$(security find-identity -v -p codesigning "$check_keychain")
    certificate_identity=$(printf '%s\n' "$identities" | grep -F "($DEVELOPMENT_TEAM)" | head -1 |
        sed -n 's/.*"\(.*\)".*/\1/p' || true)
    [ -n "$certificate_identity" ] || {
        security delete-keychain "$check_keychain" 2>/dev/null || true
        check_keychain=""
        die "$cert has no code-signing identity for team $DEVELOPMENT_TEAM"
    }
    security delete-keychain "$check_keychain" 2>/dev/null || true
    check_keychain=""
fi

echo "ci_signing_material: repository $repo"
echo "  team:            $DEVELOPMENT_TEAM"
echo "  bundle:          $TOLKARA_BUNDLE_ID"
case "$TOLKARA_KEYCHAIN_GROUP" in
    "$DEVELOPMENT_TEAM."*) echo "  keychain group:  $TOLKARA_KEYCHAIN_GROUP";;
    *) echo "  keychain group:  $DEVELOPMENT_TEAM.$TOLKARA_KEYCHAIN_GROUP";;
esac
echo "  app profile:     $(profile_summary app)"
echo "  tunnel profile:  $(profile_summary tunnel)"
if [ -n "$certificate_identity" ]; then
    echo "  certificate:     $certificate_identity"
fi
[ -z "$device" ] || echo "  device:          $device"

if [ "$upload" = 0 ]; then
    echo "ci_signing_material: --no-upload: nothing changed on GitHub"
    exit 0
fi

gh api "repos/$repo" --jq .full_name > /dev/null ||
    die "gh cannot reach $repo; run 'gh auth login' for the right account"

gh variable set DEVELOPMENT_TEAM --repo "$repo" --body "$DEVELOPMENT_TEAM" > /dev/null
gh variable set TOLKARA_BUNDLE_ID --repo "$repo" --body "$TOLKARA_BUNDLE_ID" > /dev/null
gh variable set TOLKARA_KEYCHAIN_GROUP --repo "$repo" --body "$TOLKARA_KEYCHAIN_GROUP" > /dev/null

base64 < "$cert" | gh secret set SIGNING_CERT_P12_BASE64 --repo "$repo" > /dev/null
printf '%s' "$cert_password" | gh secret set SIGNING_CERT_PASSWORD --repo "$repo" > /dev/null
base64 < "$app_profile" | gh secret set PROFILE_APP_BASE64 --repo "$repo" > /dev/null
base64 < "$tunnel_profile" | gh secret set PROFILE_TUNNEL_BASE64 --repo "$repo" > /dev/null

echo "ci_signing_material: PASS - variables and secrets set on $repo"
echo "Next, dispatch 'Developer service (signed)' for this source:"
echo "  gh workflow run developer-service-signed.yml --repo $repo --ref ci/signed-developer-service \\"
echo "      -f source_ref=$(git rev-parse --abbrev-ref HEAD)"
