# Built-in StikJIT: isolated feasibility gate

The installed Developer-service app and its game data are **not** test targets.
The experimental target is the separate External-JIT app, with no guest import
or guest launch until executable memory has been prepared and the helper has
detached. Keep the internal and SD game installations untouched.

StikJIT 2.0.1 is MPL-2.0, pinned by SHA-256 in
`.github/workflows/stikjit-compatibility.yml`. The XCFramework is downloaded
into ignored build output, not committed. The app's MIT license and bundled
third-party notices must remain accurate if a distributable build embeds it.

## Measured prerequisite

The release Swift module fails to import on the Intel Mac's Xcode 26.3
(Swift interface parse errors). The older 1.9.0 framework fails there too.
Test the pinned release on GitHub's Xcode 27 runner before wiring a helper.
The runner now typechecks `wolkaraforever/tools/jit/PreparationProbe.swift`
against the release API. A typecheck proves only toolchain compatibility and
the API shape, not JIT on a device. A separate, request-rejecting helper fixture
is compiled without signing; it cannot enable JIT or run a guest.

## Integration gates

1. Keep the existing `DebuggerArena` `brk #0xf00d` region/detach protocol;
   use StikJIT's developer-defined universal script. Never attach after guest
   entry. Refuse guest entry while attached or without executable memory.
2. Add a separately signed helper app extension to the External-JIT target
   only. A process cannot debug itself. Require `get-task-allow`, Developer
   Mode, a device-local pairing file, and a working *existing* LocalDevVPN.
   Never reuse Husk's private pairing file or the Developer-service enrollment.
3. Use a dedicated serial helper queue for preparation, attachment and
   detachment. No fallback from a failed JIT method to guest entry.
4. First device test: app and helper install together, DDI preparation,
   debugger detach, then verify the prepared RX mapping with a synthetic
   fixture. No game files are needed for this gate.
5. Only after the fixture passes on the user's iPad may a separately confirmed
   game-file import or SD-card launch be attempted. Preserve the existing app
   and its internal game files throughout.

Husk's built-in method still requires LocalDevVPN. It avoids creating a new
WolkaraForever VPN configuration, which the iPad currently rejects at
`saveToPreferences` with `NEVPNErrorDomain:5`. Husk working on this iPad is
evidence of feasibility, **not** a Tolkara device result.
