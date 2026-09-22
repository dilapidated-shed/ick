# Android release compiler gate

The goal is stronger than “ICK can emit some AArch64 code.” The goal is that an Android release can be rebuilt from source using an explicitly qualified ICK toolchain without hidden target assumptions.

## What is already demonstrated

The historical GCC-derived ICK source at `isomorphisms/rhs` commit `7458b3c29fe535eb7dda3b1c756b362cee5c889d` has a successful AArch64 qualification run (`32538975306`). That run builds a relocatable AArch64 ICK cross compiler, checks ordinary ELF output and the ICK complex representation, executes focused tests under QEMU, and links an ICK-produced object into an Android shared library with the pinned NDK.

That RHS commit is provenance, not the current source location. ICK now owns its compiler source through the pinned `gcc/` reference plus `ick/source/` and `ick/PRUNE`.

At ICK PR #4 head `37c30cdb2d557bad8c811e2669f629a79ff4e5b3`, whose file tree was merged unchanged to `main`, the current source passed:

- the focused C-only pruning/language gate;
- the AArch64 foundation gate; and
- the four-ABI Android compiler/object boundary for `arm64-v8a`, `armeabi-v7a`, `x86_64`, and `x86`.

For each of those four ABIs, the matrix builds the materialized ICK compiler, checks target identity and ELF output, compiles ordinary C and the production ICK complex boundary as PIC, links through the pinned Android NDK at API 21, compares the public scalar ABI boundary with the NDK reference compiler, checks unexpected helper symbols, rejects a mismatched target, and verifies ABI-specific load alignment and calling-convention constraints.

Wegert also has historical isolated AArch64 complex-math-object evidence from ICK. That is not the same as building the complete Wegert native library with ICK.

## Gaps that remain

- execute the current four-ABI fixtures on Android runtimes rather than relying only on compiler/object/link qualification and the older GNU/Linux AArch64 QEMU receipt;
- qualify a complete Android ICK driver/sysroot boundary beyond the focused source/object path, where needed;
- build the complete Wegert native library with ICK for each release ABI and compare its public C behavior with the reference build;
- build the release APK from source and verify its packaged native-library set;
- make an F-Droid source build rebuild the required ICK compiler/artifacts and Wegert without a fallback compiler;
- keep broader compiler features such as arbitrary NDK headers, C++ interop, TLS, sanitizers, LTO, and long-double behavior outside this gate until separately qualified.

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

Current status of the focused release qualification:

| ABI | compiler | Android object/link | Android run | Wegert library | release APK |
| --- | --- | --- | --- | --- | --- |
| arm64-v8a | proven | proven | open | open | open |
| armeabi-v7a | proven | proven | open | open | open |
| x86_64 | proven | proven | open | open | open |
| x86 | proven | proven | open | open | open |

“Proven” here means the focused compiler/object/link boundary passed on the pinned ICK source and NDK inputs. It does not silently promote Android runtime execution, the complete Wegert library, APK packaging, or F-Droid release rebuilding.

The historical AArch64 Wegert complex-math object remains useful evidence, but it is narrower than the `Wegert library` column.

## Android-version policy

`minSdk` is a release compatibility statement, not an ICK language feature. The current NDK lane qualifies the focused native boundary at API 21 rather than inheriting an arbitrary application `minSdk`. Older Android versions may be covered by additional pinned old-NDK lanes. Each old lane must run the same ABI/runtime checks instead of assuming that an old compiler is compatible merely because it accepts the source.

## Graphics is separate

The compiler gate must not require GLES 3. Wegert's current GLES 3 implementation and manifest requirement are application choices. A GLES 2 compatibility renderer, if implemented, should be qualified independently and selected by runtime capability.

## F-Droid rule for ICK adoption

The ordinary NDK compiler may remain the F-Droid release compiler until the remaining runtime, Wegert-library, APK-packaging, and source-rebuild gates are genuinely green. When ICK becomes part of the F-Droid build, F-Droid must be able to rebuild the compiler or its required source-derived artifacts from pinned, redistributable source; a checked-in opaque compiler binary is not the foundation.
