# Android ARM32 scalar memory

This repair follows scalar-call source
`13c23a41029a6ef973f85306d2cc4627d95c6606` on `arm32-d-scalar-linkage`.
It fixes accepted scalar programs that previously generated incorrect memory
accesses. The target remains `armv7a-linux-androideabi21`, A32, AAPCS32 base
PCS/softfp, 32-bit pointers and 8-byte public-call stack alignment.

## Reproduced defects

The prior compiler accepted `return *pointer` for `long`, `ulong` and `double`,
but loaded only the low word. It also accepted an indirect assignment of those
types while saving and storing only one word. These were wrong-code paths, not
diagnosed unsupported features.

The independent assembly in `scalar_memory_harness.s` demonstrates both defects
with the previous compiler. Compile `scalar_memory.d` with `-version=MemoryBaseline`
and assemble the harness with `-Wa,-defsym,MEMORY_BASELINE=1`: compilation and
linking succeed, then execution exits **1** because the high load word is wrong.
Also assemble with `-Wa,-defsym,MEMORY_START_STORE=1` to skip the load stages:
execution exits **4** because the high store word remains unchanged.

Two related global-storage defects were found during review. Bool globals had
four-byte ELF objects despite D's one-byte bool storage. The ELF writer also
declared `.data` alignment as four even when individual symbols required eight,
and scalar lowering ignored explicit declaration alignment.

## Corrected representation

| Value | Register/frame representation | Memory representation |
|---|---|---|
| `bool` | One core-register/stack word | One byte; `LDRB` / `STRB` |
| `int`, `uint`, `float`, pointer | One word | Four bytes |
| `long`, `ulong`, `double` | Two words, result in `r0:r1` | Eight bytes; both words loaded/stored |

Indirect assignment saves the entire right-hand value before computing the
destination. A destination expression may call a function and overwrite
caller-saved registers. The saved value is restored for the store and remains
the assignment expression's result. The destination address is evaluated once.

Scalar pointer indexing scales by the actual element size: one, four or eight
bytes. The frontend converts the index to target `size_t`; 32-bit address
arithmetic also handles negative indices into caller-owned buffers.

Global payload size is separate from declaration alignment. Explicit `align`
attributes are honored, and the ELF writer carries the maximum required data
alignment into both section file padding and `sh_addralign`. Bool objects remain
one byte even when explicitly aligned to sixteen.

The existing float4 dereference path remains supported. Vector indexing,
aggregate memory values, other narrow integer types, TLS globals, local-address
lowering, ref/out/lazy parameters and indirect function calls retain their
rejection boundaries. No runtime provider or runtime startup implementation is
introduced.

## Independent qualification

`verify.py` compiles the D fixture **without `-betterC`**, verifies its ELF data
and ModuleInfo contract, links it to the separate A32 harness and executes it
under QEMU. The harness owns expected values, input/output buffers, guard bytes
and comparisons. It also checks stack restoration and callee-saved sentinels.

| Stages | Checks |
|---|---|
| 1–6 | Full-width signed/unsigned/double pointer loads and stores, assignment results, unequal high/low words, negative zero and a NaN payload |
| 7–9 | Existing int, float and pointer-sized accesses |
| 10–12 | Pair stores through callbacks that overwrite caller-saved core and VFP registers |
| 13–15 | Bool dereference, defined/imported bool globals, false beside nonzero bytes, adjacent-byte preservation |
| 16–22 | Indexed scalar loads/stores/results, negative indices and adjacent-element preservation |
| 23–25 | Indexed assignments with separate base-address and index callbacks; each callback must run once |
| 26 | Linked long/double addresses and payloads; explicitly aligned bool address and byte payload |
| 31–32 | Test-only registration/unregistration contract for the ordinary-D module |

The harness's data ends four bytes after a sixteen-byte boundary and is linked
before the compiler-produced object. Thus its alignment test does not benefit
from accidental alignment of the preceding input section. Object inspection
separately checks the data section alignment/file offset and the exact size,
offset alignment and payload of every fixture global.

Two source mutants are run through separate instances of the actual outer
verifier. `MemoryWrongHighReturn` must reach execution and fail at stage **1**;
`MemoryTruncatedStore` returns the correct pair but writes only one word and must
fail at stage **4**. A compilation, linking, ELF or environment error cannot
satisfy either control. The harness maps any failed-check exit code that would
truncate to zero to 255.

The existing ordinary-D boundary ladder additionally requires aggregate pointer
elements, unsupported narrow elements, vector indexing and TLS bool globals to
pass frontend semantics, fail at the intended backend diagnostic, and remove a
deliberately stale output object.

## Local results

Build host: Ubuntu 24.04 x86_64. Bootstrap: SHA-verified DMD 2.113.0 archive
`b342ab8bd40cc0c46407692b31d7cd69661ff01da686234f426949e881727294`.
Assembler/linker: Clang/LLD 18.1.3. Execution: QEMU 8.2.2.

| Result | Status |
|---|---|
| Previous compiler reproduces wrong load and wrong store separately | PASS: execution exits 1 and 4 respectively |
| Candidate owned compiler build | PASS |
| Complete scalar-memory oracle | PASS: execution exits 0 |
| Both memory mutants rejected by the actual outer verifier at their exact execution stages | PASS |
| ELF global sizes, initializers and alignment; PIC shared-object link with `-z text` | PASS |
| Complete existing Android ARM32 verifier, including C/D calls, scalar arithmetic, softfp, registration, negative controls and NEON FFT | PASS |
| `.text` bytes for the existing C scalar, NEON FFT and ordinary-D C-linkage fixtures compared with the previous compiler | Identical |
| Existing AArch64 comparison/NaN regression | PASS |
| Android druntime link | NOT_QUALIFIED |
| Physical-device execution | NOT_RUN |

Previous compiler SHA-256:
`4f7fdafb74b933553ddd0025dc3f3780d97a84c29933320663f8fbbc9267cfde`.
Candidate compiler SHA-256:
`660b126ecf984b7004f47f7a90fc7abcb99e82da0fb8c15c11f27c7f8b6fc48f`.
Candidate scalar-memory object SHA-256:
`0a7aa51915961a0eecc7910dc765e750b8fda273d86beaac14bcd5bbdd6fb278`.
Candidate oracle SHA-256:
`a1e8cec405ec83b1106aeca8f60b5bae8171d5e6f66164d9a1b8079c7986ce76`.

These identify the local validation. Hosted builds preserve their own digests
in `scalar-memory-provenance.txt`, inspection in `scalar-memory-readelf.txt`,
and mutant receipts/logs in the existing exact-source-head ARM32 artifact.
The scalar smoke object's data-section padding and alignment metadata change
as required by the global-alignment correction; its instruction bytes do not.

## Next real-runtime boundary

A direct probe of the unmodified matching DMD 2.113.0
`druntime/src/rt/sections_elf_shared.d` fails **in frontend imports**, before
reaching ARM32 lowering. Both the previous and repaired compiler show the same
boundary. The candidate was invoked with `-conf=`, the explicit matching runtime
`import` and `src` paths, `-target=armv7a-linux-androideabi21 -c -o-`, and the actual
provider source. It exits 1.

1. `core/stdc/config.d` has no DigitalMars + ARM declaration for `c_long_double`.
   Its architecture selector covers X86, X86_64 and AArch64. The first diagnostic
   is the missing identifier at line 327.
2. `target.d:va_listType()` selects `char*` for Posix ARM, while matching
   `core/stdc/stdarg.d` declares AAPCS32 `va_list` as the `std.__va_list` struct
   containing a pointer. The mismatch causes seven `pragma(printf/scanf)`
   signature errors in `core/stdc/stdio.d`.

The exact runtime source pins remain in `RUNTIME.lock`; no runtime file or pin
was changed. The probed provider SHA-256 is
`c0638931a15bce7dc5cb007c0417811481f1df2367c5674109404f1acd1974ec`.
The `core/stdc/config.d` source/import SHA-256 is
`3b31b94a7a77aa02109693ac98882ba1d2cf0b7e2a68ca35ff61a8f9d52e3302`;
`core/stdc/stdarg.d` is
`a85cdec604e91261e5d931574338cbd63d3a19632ffb685aebe3a0e26d91cff8`.

Those frontend compatibility defects are repaired with an exact runtime overlay
and a compiler-side AAPCS32 va_list fix. The next qualified step treats struct
fields as layout-only declarations and admits context-free static struct methods.
The real provider now traverses `DSO` and stops at `opApply`'s unsupported delegate
parameter, recorded in [RUNTIME_PROVIDER_BOUNDARY.md](RUNTIME_PROVIDER_BOUNDARY.md).
Aggregate values, instance methods, slices, delegates, containers, TLS and
lifecycle remain outside the scalar qualification.

The execution above is a **QEMU Linux-syscall oracle around Android-target
objects**. Its `_d_dso_registry` is test-only and validates the compiler's
metadata contract. It does not establish an Android runtime link or device
execution.
