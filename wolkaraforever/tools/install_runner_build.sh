#!/bin/bash
# Download a signed Developer-service build from GitHub Actions, verify it,
# install it on the connected iPad, enroll Developer service when needed, and
# leave the normal WolkaraForever launcher running.
#
# Run this on a Mac with Xcode, XcodeGen and the iPad connected; the GitHub
# runner cannot reach the device or perform enrollment.
#
# usage:
#   wolkaraforever/tools/install_runner_build.sh [--ipa PATH] [--run RUN_ID]
#       [--repo OWNER/REPO] [--replace-running] [--force-kill] [--no-launch]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=wolkaraforever/tools/env.sh
. wolkaraforever/tools/env.sh
TOOLS=$ROOT/wolkaraforever/tools

ipa=""
run=""
repo=""
replace_running=0
force_kill=0
no_launch=0
ipa_dir=""
tmp=""

die() { echo "install_runner_build: $*" >&2; exit 2; }

cleanup() {
    [ -z "$ipa_dir" ] || rm -rf "$ipa_dir"
    [ -z "$tmp" ] || rm -rf "$tmp"
}
trap cleanup EXIT

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --ipa) ipa=${2:-}; shift 2;;
        --run) run=${2:-}; shift 2;;
        --repo) repo=${2:-}; shift 2;;
        --replace-running) replace_running=1; shift;;
        --force-kill) replace_running=1; force_kill=1; shift;;
        --no-launch) no_launch=1; shift;;
        -h|--help) usage; exit 0;;
        *) die "unknown argument: $1";;
    esac
done

[ "$(uname -s)" = Darwin ] || die "this must run on a Mac with Xcode"
[ -n "${DEVICE:-}" ] || die "DEVICE is not set in local.env (run wolkaraforever/tools/device_variables.sh --write)"
[ -n "${TOLKARA_BUNDLE_ID:-}" ] || die "TOLKARA_BUNDLE_ID is not set in local.env"
[ -n "${DEVELOPMENT_TEAM:-}" ] || die "DEVELOPMENT_TEAM is not set in local.env"
[ -n "${TOLKARA_KEYCHAIN_GROUP:-}" ] || die "TOLKARA_KEYCHAIN_GROUP is not set in local.env"
command -v xcrun >/dev/null || die "xcrun is missing; install Xcode and run 'sudo xcode-select -s /Applications/Xcode.app/Contents/Developer'"
command -v python3 >/dev/null || die "python3 is missing"

if [ -z "$ipa" ]; then
    command -v gh >/dev/null || die "gh is missing; install it with 'brew install gh' and run 'gh auth login'"
    if [ -z "$repo" ]; then
        url=$(git remote get-url fork 2>/dev/null || git remote get-url origin 2>/dev/null || true)
        [ -n "$url" ] || die "no git remote; pass --repo OWNER/REPO"
        repo=$(printf '%s' "$url" | sed -E 's#.*github\.com[:/]##; s#\.git$##')
    fi
    if [ -z "$run" ]; then
        run=$(gh run list --repo "$repo" --workflow "Developer service (signed)" --limit 50 \
            --json databaseId,conclusion \
            --jq '[.[] | select(.conclusion == "success")][0].databaseId')
        [ -n "$run" ] && [ "$run" != null ] ||
            die "no successful 'Developer service (signed)' run on $repo yet"
    fi
    echo "install_runner_build: downloading run $run from $repo"
    ipa_dir=$(mktemp -d "${TMPDIR:-/tmp}/wolkaraforever-run.XXXXXX")
    gh run download "$run" --repo "$repo" -n WolkaraForever-developer-service -D "$ipa_dir" ||
        die "cannot download the artifact; if it expired, dispatch the workflow again"
    ipa=$(find "$ipa_dir" -maxdepth 1 -name '*.ipa' -print | head -1)
    [ -n "$ipa" ] || die "the downloaded artifact has no .ipa"
else
    case "$ipa" in /*) ;; *) ipa="$PWD/$ipa";; esac
    [ -f "$ipa" ] || die "the .ipa does not exist: $ipa"
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/wolkaraforever-install.XXXXXX")

# Verify before touching the device. The report is kept next to the downloaded
# artifact and printed, so a failed install has an exact record of what passed.
manifest=$(find "$(dirname "$ipa")" -maxdepth 2 -name 'WolkaraForever-developer-service.build.txt' -print | head -1 || true)
source_revision=""
source_ref=""
if [ -n "$manifest" ]; then
    source_revision=$(sed -n 's/^source_revision=//p' "$manifest" | head -1)
    source_ref=$(sed -n 's/^source_ref=//p' "$manifest" | head -1)
fi
report="$tmp/$(basename "${ipa%.ipa}").verification.txt"
TOLKARA_SOURCE_REVISION="$source_revision" TOLKARA_SOURCE_REF="$source_ref" \
    "$TOOLS/verify_developer_service_ipa.sh" "$ipa" "$report" ||
    die "the downloaded build did not verify; nothing was installed"
cat "$report"

app="$tmp/Payload/Tolkara.app"
rm -rf "$tmp/Payload"
unzip -qq "$ipa" -d "$tmp" || die "cannot unpack the .ipa"
[ -d "$app" ] || die "the .ipa does not contain Payload/Tolkara.app"

# Never replace the app underneath a live client: on 2026-10-15 that left a CASC
# index slot occupied and every later launch failed. Same guard as install.sh.
pid=$("$TOOLS/running_app.sh" "$DEVICE" "$TOLKARA_BUNDLE_ID" || true)
if [ -n "${pid:-}" ]; then
    if [ "$replace_running" != 1 ]; then
        cat >&2 <<MESSAGE
install_runner_build: THE GAME IS RUNNING (pid $pid). Quit it on the iPad, or run
                     this again with --replace-running to stop it cleanly first.
MESSAGE
        exit 2
    fi
    echo "install_runner_build: stopping the running game (pid $pid)"
    xcrun devicectl device process signal --device "$DEVICE" --pid "$pid" --signal SIGTERM >/dev/null 2>&1 || true
    xcrun devicectl device process awaitTermination --device "$DEVICE" --pid "$pid" --timeout 30 >/dev/null 2>&1 || true
    if [ -n "$("$TOOLS/running_app.sh" "$DEVICE" "$TOLKARA_BUNDLE_ID" || true)" ] && [ "$force_kill" != 1 ]; then
        die "the game did not stop after SIGTERM and 30 s; rerun with --force-kill if you accept interrupting a write"
    fi
    if [ -n "$("$TOOLS/running_app.sh" "$DEVICE" "$TOLKARA_BUNDLE_ID" || true)" ]; then
        xcrun devicectl device process signal --device "$DEVICE" --pid "$pid" --signal SIGKILL >/dev/null 2>&1 || true
        xcrun devicectl device process awaitTermination --device "$DEVICE" --pid "$pid" --timeout 20 >/dev/null 2>&1 || true
    fi
    [ -z "$("$TOOLS/running_app.sh" "$DEVICE" "$TOLKARA_BUNDLE_ID" || true)" ] ||
        die "the game would not stop; close it on the iPad and try again"
fi


cleanup_needed=0
finalize_launcher() {
    [ "$cleanup_needed" = 1 ] || return 0
    [ "$no_launch" = 0 ] || return 0
    echo "install_runner_build: returning the normal launcher" >&2
    xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$TOLKARA_BUNDLE_ID" || {
        echo "install_runner_build: could not launch the normal launcher; unlock the iPad and run wolkaraforever/tools/pilot.sh launch" >&2
        return 1
    }
}
finish_install() {
    local rc=$?
    trap - EXIT
    finalize_launcher || rc=1
    cleanup
    exit "$rc"
}
trap finish_install EXIT

echo "install_runner_build: installing $TOLKARA_BUNDLE_ID on $DEVICE"
xcrun devicectl device install app --device "$DEVICE" "$app"

cleanup_needed=1

# Enrollment is Developer-service work. The app keeps an existing pin across an
# install, so this usually verifies rather than replaces it.
echo "install_runner_build: developer-service enrollment"
wolkaraforever/tools/prepare.sh
set +e
( cd build/platform && "$ROOT/wolkaraforever/tools/after_install.sh" developer-service ) 2>&1 |
    tee "$tmp/enroll.log"
enroll_rc=${PIPESTATUS[0]}
set -e
[ "$enroll_rc" -eq 0 ] ||
    die "enrollment failed; the app is installed. Keep the iPad unlocked and connected, then run: (cd build/platform && tools/enroll.sh)"
if grep -q "enrollment not attempted" "$tmp/enroll.log"; then
    die "the app is installed, but enrollment was not attempted because the iPad was not visible to the pairing bridge. Connect it by USB and run: (cd build/platform && tools/enroll.sh)"
fi

installed_line=$(xcrun devicectl device info apps --device "$DEVICE" 2>/dev/null | grep -i "$TOLKARA_BUNDLE_ID" || true)
if [ -n "$installed_line" ]; then
    echo "install_runner_build: installed $installed_line"
else
    echo "install_runner_build: app catalogue did not list the bundle; requiring a successful direct launch" >&2
    [ "$no_launch" = 0 ] || die "cannot verify this install with --no-launch when the app catalogue is incomplete"
fi

if [ "$no_launch" = 0 ]; then
    xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$TOLKARA_BUNDLE_ID"
fi
cleanup_needed=0
if [ "$no_launch" = 0 ]; then
    echo "install_runner_build: PASS - the runner build is installed and the launcher is running"
else
    echo "install_runner_build: installed and enrolled; normal launcher was not requested"
fi
