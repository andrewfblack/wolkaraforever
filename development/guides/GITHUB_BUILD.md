# Building on a GitHub runner

A GitHub-hosted macOS runner can compile and sign WolkaraForever, but it cannot
reach your iPad. Installation and Developer-service enrollment always happen on
a Mac with Xcode, because enrollment uses Apple's private
`MobileDevice.framework` and `xcrun devicectl`.

This page therefore splits the work:

| Where | What it does |
| --- | --- |
| GitHub runner (`macos-26`) | Checks out a branch, builds the integrated **Tolkara** target for Developer service, signs the app and extension with your Apple Development identity, verifies the result, and uploads a signed `.ipa`. |
| Your Mac (Xcode required) | Once: builds/installs locally to create the certificate, App IDs, capabilities and profiles. Then: downloads the runner's `.ipa`, verifies it, installs it, enrolls Developer service and launches the app. |

The runner never sees the iPad, and no game files or account data enter the
workflow.

## 1. Install Xcode on the Mac

Xcode 26.0–26.3 are universal and run on Intel Macs with macOS Sequoia 15.6 or
later. Use the universal `.xip` from [Apple Developer downloads](https://developer.apple.com/download/all/);
some helper tools (`xcodes`) have downloaded the Apple-silicon-only image on
Intel. Xcode 26.4 and later require macOS Tahoe 26.2.

```sh
# If Xcode is still an expanded .xip, move the app into /Applications first.
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
xcodebuild -version

brew install xcodegen gh
gh auth login
```

`xcodebuild -version` must print 26.x. The repository's own prerequisites check
is also useful: `wolkaraforever/tools/install_prerequisites.sh --check`.

## 2. Configure this checkout

Use your own identifiers. The bundle ID and Keychain group must stay stable so a
new build replaces the app without losing its data or enrollment.

```sh
git clone https://github.com/andrewfblack/wolkaraforever.git
cd wolkaraforever
git checkout feature/external-install-records
cp local.env.example local.env
```

Set at least these in `local.env`:

```sh
DEVELOPMENT_TEAM=YOUR_TEAM_ID
TOLKARA_BUNDLE_ID=your.unique.bundle.id
TOLKARA_KEYCHAIN_GROUP=your.unique.bundle.id.authorization
```

Connect the iPad by USB, unlock it, trust the Mac, and enable Developer Mode.
Then let the device helper fill in `DEVICE`:

```sh
wolkaraforever/tools/device_variables.sh --write
wolkaraforever/tools/preflight.sh
```

## 3. One-time local build and enrollment

This is the bootstrap that creates the signing material the runner needs. It
also proves the app works before any CI is involved.

```sh
wolkaraforever/tools/install.sh
```

Xcode automatic signing creates the Apple Development certificate, both App IDs,
the capabilities (Network Extension, Increased Memory Limit, Extended Virtual
Addressing, Keychain Sharing) and the two development profiles that include
this iPad. The installer then enrolls Developer service and returns the normal
launcher.

If Xcode reports a signing error, open the generated project and repair signing
as described in [BUILDING.md](BUILDING.md#2-configure-your-own-signing):

```sh
wolkaraforever/tools/generate.sh
open build/platform/Tolkara.xcodeproj
```

Select **Tolkara** and **LocalAuthorizationTunnel**, choose your team under
**Signing & Capabilities**, and let Xcode repair provisioning. Then run the
installer again.

## 4. Put the signing material in GitHub

Create or select an Apple Development certificate in Xcode: **Settings >
Accounts > Manage Certificates… > + > Apple Development**. Then export it with
its private key from Keychain Access:

1. Keychain Access > **login** > **My Certificates**.
2. Select `Apple Development: <name> (<TEAM>)` together with its private key.
3. Right-click > **Export…** > **Personal Information Exchange (.p12)**, and set
   a password.
4. Run the export helper:

```sh
wolkaraforever/tools/ci_signing_material.sh --cert ~/Downloads/AppleDevelopment.p12
```

The helper finds the newest valid app profile and tunnel profile in Xcode's
profile directory, checks that they include this iPad, the packet-tunnel
capability, the memory capabilities and the shared Keychain group, and then sets
these on the fork:

- repository variables: `DEVELOPMENT_TEAM`, `TOLKARA_BUNDLE_ID`,
  `TOLKARA_KEYCHAIN_GROUP`;
- repository secrets: `SIGNING_CERT_P12_BASE64`, `SIGNING_CERT_PASSWORD`,
  `PROFILE_APP_BASE64`, `PROFILE_TUNNEL_BASE64`.

Use `--no-upload` first if you only want to see which profiles and certificate
it found. It never prints the certificate, password or profile contents.

The private key is stored only in GitHub's encrypted Actions secrets. The
workflow is manual and reads those secrets only on the trusted repository, not
for pull requests from forks.

## 5. Dispatch the signed build

Pushing `ci/signed-developer-service` triggers a **build-only** runner check
against `feature/external-install-records`. It uploads an unsigned `.zip` for
inspection; this is **not installable**. GitHub permits manual dispatch only
for a workflow that already exists on the repository's default branch. After
the CI pull request is reviewed and merged to `main`, run the signed workflow;
the input says which trusted source branch to build:

```sh
gh workflow run developer-service-signed.yml \
    --repo andrewfblack/wolkaraforever \
    --ref main \
    -f source_ref=feature/external-install-records
gh run watch --repo andrewfblack/wolkaraforever
```

Or use **Actions > Developer service (signed) > Run workflow** and choose
`main`. The default `source_ref` is the current feature branch; set it to
`main` or another **trusted** branch when needed. A signed run executes the
selected branch's Xcode build scripts with access to signing material; never
dispatch it for an untrusted pull request or arbitrary contributor branch.

The run uploads `WolkaraForever-developer-service` containing:

- `WolkaraForever-developer-service.ipa`
- `WolkaraForever-developer-service.verification.txt`
- `WolkaraForever-developer-service.build.txt`

The verification report names the source revision, bundle ID, signing team,
both profile names and expiry dates, the capabilities, and the IPA's SHA-256.
The run also fails before installing anything if the certificate or either
profile is not usable for this bundle.

## 6. Install the runner build on the iPad

Keep the iPad unlocked and connected, then:

```sh
wolkaraforever/tools/install_runner_build.sh
```

The helper downloads the newest successful artifact, verifies it, stops a
running game only when you ask it to, installs the app, verifies or renews
Developer-service enrollment, checks that the device lists the bundle, and
launches the normal launcher.

Useful variants:

```sh
# A specific downloaded artifact
wolkaraforever/tools/install_runner_build.sh --ipa ~/Downloads/WolkaraForever-developer-service.ipa

# A specific workflow run
wolkaraforever/tools/install_runner_build.sh --run 1234567890

# The game is open; stop it cleanly first
wolkaraforever/tools/install_runner_build.sh --replace-running
```

The installer refuses to replace the app while the game is running. On
2026-10-15 that left a CASC index slot occupied and every later launch failed;
`--force-kill` exists only for the case where you accept interrupting a write.

## What is and is not evidence

The workflow proves that the source compiles, the app and extension sign with
your team, the two profiles match the bundle IDs and the capabilities, and the
packaged IPA verifies. That is source-level and packaging evidence, not a device
result.

A successful `install_runner_build.sh` proves the device accepted and lists the
build and that enrollment completed. Actual game launch and gameplay remain a
device or human result, recorded as described in
[COMPATIBILITY.md](../../COMPATIBILITY.md) and
[TESTING.md](../testing/TESTING.md).

## Troubleshooting

| Problem | Action |
| --- | --- |
| `no usable app profile` or `no usable tunnel profile` | The profile is missing a device, a capability or the Keychain group. Run the local `install.sh` again, check both targets under **Signing & Capabilities**, then rerun the export helper. |
| `the app was built as …` | The workflow's bundle ID does not match the profiles. Set the `TOLKARA_BUNDLE_ID` variable or pass `-f bundle_id=…`. |
| `no code-signing identity for team …` | Re-export the .p12 with its private key; the certificate may be expired or from another team. |
| `the imported certificate has no identity` | The .p12 has a certificate but no private key, or the password is wrong. |
| `the downloaded build did not verify` | Read the verification report first. Re-dispatch the workflow after fixing the named setting; nothing was installed. |
| `enrollment not attempted` | The iPad was not visible to the pairing bridge. Connect it by USB, trust the Mac, and run `cd build/platform && tools/enroll.sh`. |
| The artifact expired | GitHub keeps artifacts for 90 days. Dispatch the workflow again. |
| Xcode 26.3 on Intel installed the Apple-silicon image | Use the universal `.xip` from Apple's download page rather than a helper that picked the arm64-only image. |
