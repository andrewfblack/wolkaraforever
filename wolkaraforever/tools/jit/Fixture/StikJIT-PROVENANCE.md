# Vendored StikJIT

`StikJIT.xcframework` is the `ios-arm64` slice of the framework released at
`https://github.com/StikDebug/StikJIT/releases/download/2.0.1/StikJIT.xcframework.zip`.

- Upstream framework version: **StikJIT 2.0.1** (MPL-2.0, see `StikJIT-MPL-2.0.txt`).
- Upstream archive SHA-256: `c376687326a785f5ed1da8caca08adc709b56919019dd751bca059b92b175d95`.
- Modification: the `tvos-arm64` slice was removed, and the xcframework `Info.plist`
  was rewritten to advertise only `ios-arm64`. No framework binary, header, module
  interface or JavaScript file was edited.
- `StikJIT-VENDOR.sha256` records the exact bytes of this vendored copy
  (`cd wolkaraforever/tools/jit/Fixture && sha256sum -c StikJIT-VENDOR.sha256`).

The framework is MPL-2.0 covered file-level copyleft; we do not modify its files. It
is vendored so the CI build does not depend on the availability of a release download.
