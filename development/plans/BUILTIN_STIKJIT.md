# Built-in StikJIT

StikJIT is vendored at `wolkaraforever/JIT/StikJIT.xcframework` (2.0.1,
copied byte-identically from the upstream release; SHA-256 recorded in
`StikJIT-VENDOR.sha256`, license in `StikJIT-MPL-2.0.txt`, provenance in
`StikJIT-PROVENANCE.md`). It is embedded in the External-JIT diagnostics
app's new helper extension `TolkaraJITHelper.appex`, wired in by patches
0049 and 0050.

## What is built

- The diagnostics app now carries `launcher/JITHelper/` (helper extension and
  vendored framework) with the extension embedded by `TolkaraDiagnostics`.
- Tap **Play** while JIT is not prepared: the app asks its own helper, with
  an already-importing pairing file in `Documents/StikJIT/pairingFile.plist`,
  through a private `NSExtension` request restricted to `operation=enable`.
- If the process is not already prepared (`CS_DEBUGGED` is not set), the
  request asks StikJIT to prepare the device. The existing `DebuggerArena`
  `brk #0xf00d` protocol is unchanged; a prepared process can enter a guest
  exactly as before.

## What the device still has to prove

1. A sideload device on iPadOS 27 (not the Developer-service enrolled one)
   accepts the app signed with `get-task-allow` and preserves the helper.
2. The pairing file (created by iLoader) lets the helper finish DDI
   preparation and detach before guest entry.
3. The prepared arena is actually executable for a synthetic fixture.

Until (1)-(3) pass on the iPad, no game should be started through this
build; the existing iPad Developer-service app and its game data are
untouched.

The paired CI run only produces an **unsigned** IPA for local signing; Sideloadly
or iLoader signs it. No Mac Keychain or Apple private key enters GitHub.

Husk's built-in method still requires LocalDevVPN. It avoids creating a new
WolkaraForever VPN configuration, which the iPad currently rejects at
`saveToPreferences` with `NEVPNErrorDomain:5`. Husk working on this iPad is
evidence of feasibility, **not** a Tolkara device result.
