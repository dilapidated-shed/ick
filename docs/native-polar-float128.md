# Native polar runtime qualification

On x86_64 Linux, the previous native `all-target-libgcc` build asserted while
lowering `_Float128 _Complex` component stores in `__multc3` and `__divtc3`.
The implicit math-builtin lookup did not return the explicitly declared
`hypotf128`, `atan2f128`, `sinf128`, and `cosf128` family.  ICK now selects that
explicit family for the exact binary128 type.  It retains the existing
selection and widening rules for other scalar floating types.

The executable binary128 regression also exposed a separate optimized byte
inspection failure.  Promoting an address-taken complex object into SSA form
rewrote copied scalar slots to `REALPART_EXPR` and `IMAGPART_EXPR`.  Those
expressions request mathematical Cartesian components, whereas floating
complex storage contains radius and angle.  Before complex lowering, partial
storage loads now keep their memory representation.  Equivalent indirect
pointer folds exclude floating complex types, and the bit-field
canonicalization keeps storage loads separate from mathematical extraction
until complex lowering has finished.  Integer complex storage and its
Cartesian folds retain their existing behavior.

`qualification/native-polar/Makefile` materializes the exact owned compiler
source and builds and installs ICK, its own `libgcc`, startup objects, and
`libatomic`.  Host gcc/g++ perform the compiler bootstrap.  Ubuntu glibc
supplies libc, its startup objects, and scalar libm, including the binary128
math entry points.  Package and built-runtime hashes identify that boundary.
This profile does not copy a prebuilt host libgcc or substitute a host
compiler for the test consumer.

Run `make -f qualification/native-polar/Makefile build`, followed by
`make -f qualification/native-polar/Makefile check`.  Use a fresh build
directory after changing an overlay: the materializer deliberately refuses
to overwrite an existing source tree.

The gate executes 21 programs: the existing float/double layout and radial
rounding tests, the new binary128 precision and runtime byte-load tests, the
assignment and multiplication glyph tests, and both existing constant
byte-fold directions, each at O0, O2, and O3.  It also compiles the Float16
widening and binary128 construction fixtures.  The binary128 precision input
contains a 2^-100 increment, and its geometric case checks both the physical
(5, atan2(4,3)) pair and reconstructed (3,4) components.  The byte-load test
covers float, double, copied slots, explicitly alias-enabled pointer loads,
and unchanged integer complex storage.

This is an x86_64 Linux qualification.  It does not establish a foreign
Cartesian `_Complex` calling convention, Android binary128 libm support, or
physical-device acceptance.  Existing scalar consumers pinned to the earlier
compiler revision keep their separately declared prebuilt runtime boundary;
they do not acquire this new runtime profile automatically.
