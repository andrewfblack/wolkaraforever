#!/usr/bin/env python3
"""Validate one decoded provisioning profile and extract its entitlements.

The signing scripts decode a `.mobileprovision` with `security cms -D` first;
this file never parses the CMS wrapper itself. It checks exactly what makes a
development profile usable for WolkaraForever's two bundles:

  * the application identifier is the app or its tunnel extension;
  * the profile has not expired;
  * the iPad (when one is named) is provisioned;
  * the profile carries the Keychain group the app and extension share;
  * Network Extension, increased memory and extended virtual addressing are
    present on the app, and Network Extension on the extension.

Nothing here reads or prints private key material. It is used by the Mac export
helper and by the GitHub runner's signing step, so it is plain Python 3 and also
runs on Linux for its tests.
"""

import argparse
import datetime
import json
import plistlib
import sys


REQUIRED_NETWORK_EXTENSION = "packet-tunnel-provider"


class ProfileError(Exception):
    pass


def expected_identifier(team, bundle, kind):
    identifier = "%s.%s" % (team, bundle)
    return identifier if kind == "app" else identifier + ".authorization"


def normalize_keychain_group(team, group):
    group = group.strip()
    prefix = team + "."
    if group.startswith(prefix):
        group = group[len(prefix):]
    if not group:
        raise ProfileError("the Keychain group is empty")
    return team + "." + group


def load(path):
    try:
        with open(path, "rb") as source:
            value = plistlib.load(source)
    except (OSError, plistlib.InvalidFileException) as error:
        raise ProfileError("cannot read the decoded profile: %s" % error)
    if not isinstance(value, dict):
        raise ProfileError("the decoded profile is not a dictionary")
    return value


def expiration(value):
    if not isinstance(value, datetime.datetime):
        raise ProfileError("the profile has no ExpirationDate")
    if value.tzinfo is None:
        return value.replace(tzinfo=datetime.timezone.utc)
    return value


def string_list(entitlements, key):
    value = entitlements.get(key)
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ProfileError("the profile has no %s list" % key)
    return value


def inspect(path, kind, team, bundle, keychain_group, device):
    profile = load(path)
    entitlements = profile.get("Entitlements")
    if not isinstance(entitlements, dict):
        raise ProfileError("the profile has no Entitlements dictionary")

    identifier = entitlements.get("application-identifier")
    wanted = expected_identifier(team, bundle, kind)
    if identifier != wanted:
        raise ProfileError(
            "application-identifier is %r, expected %r" % (identifier, wanted)
        )

    profile_team = entitlements.get("com.apple.developer.team-identifier")
    if profile_team not in (None, team):
        raise ProfileError(
            "the profile belongs to team %r, expected %r" % (profile_team, team)
        )

    expires = expiration(profile.get("ExpirationDate"))
    if expires <= datetime.datetime.now(datetime.timezone.utc):
        raise ProfileError("the profile expired on %s" % expires.isoformat())

    devices = profile.get("ProvisionedDevices")
    if device:
        if not isinstance(devices, list) or device not in devices:
            raise ProfileError(
                "the profile does not include device %s" % device
            )

    wanted_group = normalize_keychain_group(team, keychain_group)
    groups = string_list(entitlements, "keychain-access-groups")
    if wanted_group not in groups and (team + ".*") not in groups:
        raise ProfileError(
            "the profile's keychain-access-groups (%s) do not include %s"
            % (", ".join(groups), wanted_group)
        )

    network_extensions = string_list(
        entitlements, "com.apple.developer.networking.networkextension"
    )
    if REQUIRED_NETWORK_EXTENSION not in network_extensions:
        raise ProfileError("the profile does not allow a packet tunnel provider")

    if kind == "app":
        for capability in (
            "com.apple.developer.kernel.increased-memory-limit",
            "com.apple.developer.kernel.extended-virtual-addressing",
        ):
            if entitlements.get(capability) is not True:
                raise ProfileError("the profile does not enable %s" % capability)

    name = profile.get("Name")
    uuid = profile.get("UUID")
    return {
        "name": name if isinstance(name, str) else "",
        "uuid": uuid if isinstance(uuid, str) else "",
        "app_identifier": identifier,
        "expires": expires,
        "devices": len(devices) if isinstance(devices, list) else 0,
        "entitlements": entitlements,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    command = subparsers.add_parser("inspect", help="validate one decoded profile")
    command.add_argument("--profile-plist", required=True)
    command.add_argument("--kind", choices=("app", "tunnel"), required=True)
    command.add_argument("--team", required=True)
    command.add_argument("--bundle", required=True)
    command.add_argument("--keychain-group", required=True)
    command.add_argument("--device", default="")
    command.add_argument("--entitlements-out", default="")
    command.add_argument("--json", action="store_true")
    args = parser.parse_args()

    try:
        result = inspect(
            args.profile_plist,
            args.kind,
            args.team,
            args.bundle,
            args.keychain_group,
            args.device,
        )
    except ProfileError as error:
        print("signing_profile: %s" % error, file=sys.stderr)
        return 1

    if args.entitlements_out:
        with open(args.entitlements_out, "wb") as target:
            plistlib.dump(result["entitlements"], target)

    epoch = int(result["expires"].timestamp())
    if args.json:
        print(
            json.dumps(
                {
                    "name": result["name"],
                    "uuid": result["uuid"],
                    "app_identifier": result["app_identifier"],
                    "expires": result["expires"].isoformat(),
                    "expires_epoch": epoch,
                    "devices": result["devices"],
                },
                sort_keys=True,
            )
        )
    else:
        print(
            "signing_profile: OK - %s %r (%s), %d device(s), expires %s"
            % (
                args.kind,
                result["name"],
                result["uuid"] or "no UUID",
                result["devices"],
                result["expires"].isoformat(),
            )
        )
        print("expires_epoch=%d" % epoch)
    return 0


if __name__ == "__main__":
    sys.exit(main())
