# Polar storage and extraction-only functions

The account-wide division-source migration exposed this defect in the real
Coefficient Root Dance Android Debug renderer. `crealf` and `cimagf` in
`draw_frame` uploaded stored radius/angle pairs as Cartesian coordinates.
For the first initial root, the uploaded pair was approximately
`(1.16619039, 2.60117316)` instead of `(-1, 0.6)`. The unchanged emulator drag
acceptance therefore failed. Initial complex constants were correctly stored
in polar form; this was a component-lowering defect, not a Bionic complex ABI
conversion or a graphics-driver error.

`init_dont_simulate_again` only enabled lowering for component reads when the
operand was an undefined SSA name. Functions with no other complex operation
could skip the pass. The repair also enables lowering for floating-complex
component reads, allowing the existing Cartesian extraction implementation to
run. The undefined integer-complex case remains intact. There is no application
math change, optimization override, representation change, or foreign ABI claim.

## Regression and local evidence

`ick-complex-extraction-only.c` checks float and double extraction from indexed
struct members, pointers, arguments, inline helpers, and direct language
component syntax. Separate functions prevent unrelated complex arithmetic from
accidentally enabling the pass. Expected Cartesian coordinates are independent
of the conversion implementation. A byte-copy check also requires unchanged
polar storage. The fixed Make interface runs this test and the existing polar
layout and complex-round tests at `-O0`, `-O1`, `-O2`, `-O3`, and `-Os`.

The pre-fix source was `c61e448251744a2f40ad743ebef1a027bdcd2f9d`, with the
pinned GCC reference `6294f1d9e7536e5ffcde09d1528c918d63abfef5`. Its retained
native `cc1` SHA-256 was
`a181082f120a906c86ebd8c7a2378bcc83d9694a8c533438536768f180ad1b17`.
The new regression returned 10 failures at O0 and 12 at each other level.
Both the actual Debug and Release renderer-state tests failed the first
coefficient upload with that compiler.

The local incremental validation rebuilt only the modified backend object
against the already qualified current-source object closure, using the owned
`tree.h` and `builtins.def`, regenerated the executable checksum, and linked a
separate stripped frontend. Its `cc1` SHA-256 was
`3c3886708a382cb4aff03d5d8a5fd0986f8a73359277f7bd39d71feaca7a452c`.
All 15 runtime tests passed. The existing Float16 compile test passed, and the
object-byte-fold test retained both constant `return 1` results.

Independent consumer checks using this frontend and exact NDK r29/API26
x86_64 Bionic passed both actual renderer-state executables, including captured
GLfloat uploads and initial hit coordinates. The unchanged complete Debug app
also compiled, assembled, and linked; its complex-lowering dump now computes
radius times cosine/sine before the uploads. Its library SHA-256 was
`ab75a3f6509be464a14a5f7d46736beb2dd4f60e2cf90b6b2c44e4d44cd22476`.
These local checks do not claim a clean full compiler rebuild or a new emulator
pass. The exact-head native workflow builds clean source and retains its own
compiler identity; the consumer PR retains the emulator acceptance.

## Existing separate limitation

The Float128 compile fixture fails in both pre-fix and patched local compilers
at the same `polar_math_builtins_available` assertion. The separate binary128
builtin mapping repair is tracked in ICK PR 81. This extraction repair does
not claim to resolve that pre-existing limitation, and the bounded native gate
does not describe the complete complex testsuite as passing.
