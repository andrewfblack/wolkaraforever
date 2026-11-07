#!/usr/bin/env python3
"""Tests for signing_profile.py, runnable on Linux and macOS.

    python3 wolkaraforever/tools/tests/test_signing_profile.py
"""

import datetime
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest


TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROFILE = os.path.join(TOOLS, "signing_profile.py")
TEAM = "ABCDE12345"
BUNDLE = "local.example.wolkaraforever"
GROUP = "authorization"


def profile(kind="app", **overrides):
    identifier = "%s.%s" % (TEAM, BUNDLE)
    if kind == "tunnel":
        identifier += ".authorization"
    entitlements = {
        "application-identifier": identifier,
        "com.apple.developer.team-identifier": TEAM,
        "keychain-access-groups": [TEAM + "." + GROUP, TEAM + "." + BUNDLE],
        "com.apple.developer.networking.networkextension": [
            "packet-tunnel-provider",
        ],
    }
    if kind == "app":
        entitlements["com.apple.developer.kernel.increased-memory-limit"] = True
        entitlements["com.apple.developer.kernel.extended-virtual-addressing"] = True
    entitlements.update(overrides.pop("entitlements", {}))
    value = {
        "Name": "iOS Team Provisioning Profile: " + identifier,
        "UUID": "11111111-2222-3333-4444-555555555555",
        "ExpirationDate": datetime.datetime.now(datetime.timezone.utc)
        + datetime.timedelta(days=30),
        "ProvisionedDevices": ["00008110-000000000000001E"],
        "Entitlements": entitlements,
    }
    value.update(overrides)
    return value


class SigningProfileTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.folder.name, "profile.plist")
        self.entitlements = os.path.join(self.folder.name, "entitlements.plist")

    def tearDown(self):
        self.folder.cleanup()

    def write(self, value):
        with open(self.path, "wb") as target:
            plistlib.dump(value, target)

    def inspect(self, kind="app", device="", extra=()):
        return subprocess.run(
            [
                sys.executable,
                PROFILE,
                "inspect",
                "--profile-plist",
                self.path,
                "--kind",
                kind,
                "--team",
                TEAM,
                "--bundle",
                BUNDLE,
                "--keychain-group",
                GROUP,
                "--device",
                device,
                "--entitlements-out",
                self.entitlements,
            ]
            + list(extra),
            text=True,
            capture_output=True,
        )

    def test_valid_app_profile_and_entitlements(self):
        self.write(profile())
        result = self.inspect()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("signing_profile: OK", result.stdout)
        with open(self.entitlements, "rb") as source:
            entitlements = plistlib.load(source)
        self.assertIs(
            entitlements["com.apple.developer.kernel.increased-memory-limit"], True
        )

    def test_valid_tunnel_profile(self):
        self.write(profile("tunnel"))
        result = self.inspect("tunnel")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_app_profile_is_not_a_tunnel_profile(self):
        self.write(profile())
        result = self.inspect("tunnel")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("application-identifier", result.stderr)

    def test_missing_memory_capability(self):
        self.write(
            profile(
                entitlements={
                    "com.apple.developer.kernel.increased-memory-limit": False,
                }
            )
        )
        result = self.inspect()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("increased-memory-limit", result.stderr)

    def test_missing_network_extension(self):
        self.write(profile(entitlements={"com.apple.developer.networking.networkextension": []}))
        result = self.inspect()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("packet tunnel", result.stderr)

    def test_expired_profile(self):
        self.write(
            profile(
                ExpirationDate=datetime.datetime.now(datetime.timezone.utc)
                - datetime.timedelta(days=1)
            )
        )
        result = self.inspect()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expired", result.stderr)

    def test_missing_keychain_group(self):
        self.write(
            profile(
                entitlements={
                    "keychain-access-groups": [TEAM + ".something.else"],
                }
            )
        )
        result = self.inspect()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("keychain-access-groups", result.stderr)

    def test_wildcard_keychain_group_is_accepted(self):
        self.write(
            profile(entitlements={"keychain-access-groups": [TEAM + ".*"]})
        )
        result = self.inspect()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_device_must_be_provisioned(self):
        self.write(profile())
        result = self.inspect(device="00008110-00000000000000FF")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not include device", result.stderr)

    def test_device_match(self):
        self.write(profile())
        result = self.inspect(device="00008110-000000000000001E")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_json_summary(self):
        self.write(profile())
        result = self.inspect(extra=("--json",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('"uuid": "11111111-2222-3333-4444-555555555555"', result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
