# C assignment-arrow qualification

The exact FastChat assignment probe previously rejected by ICK now compiles
with the owned rebuilt frontend. Source revision:
`2a27ad6ab4e4601c9a0e4a5fa7915712db707af0`, based on current ICK main
`e3c2a40b4edafc4d9caca55d1f7c094e6aab9589`.
The receipt-only descendant does not change compiler source.

The build reused an isolated copy of the qualified AArch64 compiler build
from source revision `7afb1820cd59c0c51d19a7e37902c14f4466f442`.
That revision's `ick/` source layer and pinned GCC reference are identical
to the main base. The owned `c-lex.cc` was copied into the isolated source,
then upstream `make all-gcc` rebuilt its object and linked the new `cc1`.
The original checkout, installed compiler and build were not changed.
The trace confirms the new `cc1` path. System C++ built the compiler itself;
all first-party regression C was compiled by the rebuilt owned ICK.

The existing materializer was also executed with Bash on the build host
(the existing file is a POSIX shell implementation; no new shell script was
authored). It verified every manifest path/hash and created fresh source.
A full content comparison found no shared-file differences between this
source and the compiler's copied source. The old cache additionally omits
unused C++/Objective-C/COBOL frontend directories, and the four new fixture
files are present only in the fresh source. The changed frontend's bytes
match the owned overlay and fresh materialization exactly.

The semantic fixture is headers-free. It compiles with warnings as errors,
links using GNU AArch64 binutils, CRT, libc and libgcc substrate already
present on the build host, and exits 0 under Linux/AArch64 QEMU. It checks
initialization, designated initialization, enum values, pointer/member
assignment, chained assignment, result value, single evaluation, macro
expansion/stringification and literal UTF-8 byte preservation. Three
negative fixtures preserve ordinary C diagnostics and reject an unsupported
neighboring glyph. These fixtures were invoked directly; the DejaGnu
harness was not run.

The direct-source and preprocessed-source optimized objects have the same
SHA256. The old compiler still rejects the exact unchanged FastChat probe;
the rebuilt compiler accepts it. Historical failure and negative-test
diagnostics are retained, along with exact invocations and artifact hashes.

This is frontend and Linux/QEMU evidence. The new compile-only step in the
existing Android foundation workflow uses its own freshly built ICK.
This receipt claims no Android APK, installed compiler release, or physical
MIRO A1 execution. Both remain `BLOCKED/NOT_RUN` for this task.

Files: `receipt.tsv`, `commands.txt`, `diagnostics.txt`, and
`compiler-trace.txt`. Fixture source is owned under
`ick/source/gcc/testsuite/gcc.dg/ick-assignment-arrow*.c`.
