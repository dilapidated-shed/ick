# Android release compiler gate

The goal is stronger than “ICK can emit some AArch64 code.” The goal is that an Android release can be rebuilt from source using an explicitly qualified ICK toolchain without hidden target assumptions.

## What is already demonstrated

The GCC-derived ICK source at `isomorphisms/rhs` commit `7458b3c29fe535eb7dda3b1c756b362cee5c889d` has a successful AArch64 qualification run (`32538975306`). That run builds a relocatable AArch64 ICK cross compiler, checks ordinary ELF output and the ICK complex representation, executes focused tests under QEMU, and links an ICK-produced object into an Android shared library with the pinned NDK.

Wegert records the same compiler provenance for its isolated AArch64 complex-math object.

This is useful evidence, but it is not yet a full Android release compiler.

## Gaps that remain

- the new squashed `gcc/` reference plus `ick/source/` source-of-truth path must reproduce the old AArch64 receipt on its own current head
- the successful Android boundary uses an AArch64 GNU/Linux-target ICK object plus Android NDK assembly/linking rather than a fully qualified Android ICK driver
- only the AArch64 boundary is qualified
- `armeabi-v7a`, `x86_64`, and `x86` Android output are not qualified
- Android-specific ABI rules must be checked explicitly, including reserved-register rules where applicable
- the current Wegert F-Droid build deliberately disables the ICK prebuilt object and therefore does not prove an ICK-built F-Droid release

## Required gate

A target is release-qualified only when all of the following are reproducible from pinned source:

1. Build the ICK compiler from the ICK source-of-truth repository.
2. Compile ordinary C at the chosen language baseline without ICK-specific syntax.
3. Compile the ICK extensions exercised by production source.
4. Produce the expected machine/object ABI and reject a mismatched target.
5. Compile PIC suitable for an Android shared library.
6. Link against the selected Android sysroot/runtime without undeclared host dependencies.
7. Verify exported and undefined symbols and fail on unexpected compiler helper routines.
8. Verify Android ABI requirements, including stack alignment, calling convention, reserved registers, relocation kinds, and ELF attributes relevant to that ABI.
9. Build and run a small native Android fixture for the target API floor.
10. Verify load-segment alignment and exercise both 4 KiB and 16 KiB Android page-size environments where the platform provides them.
11. Build the Wegert native library from source with ICK for that ABI and compare its public C boundary against the reference compiler build.
12. Build the release APK from source and verify that its native-library set is exactly the requested ABI matrix.

## Matrix

The current-NDK qualification matrix starts with:

| ABI | compiler | Android object | Android run | Wegert library | release APK |
| --- | --- | --- | --- | --- | --- |
| arm64-v8a | partial/proven | partial/proven | open | partial/proven | open |
| armeabi-v7a | open | open | open | open | open |
| x86_64 | open | open | open | open | open |
| x86 | open | open | open | open | open |

“Partial/proven” means the existing isolated boundary passed; it does not silently promote the whole target to release-qualified.

## Android-version policy

`minSdk` is a release compatibility statement, not an ICK language feature. The current NDK lane should qualify its actual minimum API rather than inheriting an arbitrary application value. Older Android versions may be covered by additional pinned old-NDK lanes. Each old lane must run the same ABI/runtime checks instead of assuming that an old compiler is compatible merely because it accepts the source.

## Graphics is separate

The compiler gate must not require GLES 3. Wegert's current GLES 3 implementation and manifest requirement are application choices. A GLES 2 compatibility renderer, if implemented, should be qualified independently and selected by runtime capability.

## F-Droid rule for ICK adoption

Until the matrix above is genuinely green, F-Droid may keep using the ordinary NDK compiler. When ICK becomes part of the F-Droid build, F-Droid must be able to rebuild the compiler or its required source-derived artifacts from pinned, redistributable source; a checked-in opaque compiler binary is not the foundation.
