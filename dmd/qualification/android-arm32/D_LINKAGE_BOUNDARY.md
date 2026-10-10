# Android ARM32 scalar D linkage

The owned DMD now emits module-level ordinary-D scalar function definitions and
direct calls for `armv7a-linux-androideabi21`, using `-c` without `-betterC`.
Three separately compiled D modules are linked to an independent A32 assembly
oracle and executed with QEMU. This qualifies the scalar object/call boundary;
Android druntime and physical-device execution remain unqualified.

This document records the initial scalar-call qualification at source
`13c23a41029a6ef973f85306d2cc4627d95c6606`. Subsequent scalar-storage repairs,
additional memory execution checks, and the exact real-runtime import blockers
are recorded in [SCALAR_MEMORY_BOUNDARY.md](SCALAR_MEMORY_BOUNDARY.md).

## Compiler change

`compiler/src/dmd/glue/arm32.d` uses `mangleExact` for both D function definitions
and direct-call relocations. The name therefore identifies the resolved module,
overload, parameter/result types, attributes and any `pragma(mangle)` override.
C linkage keeps its existing symbol handling.

A shared signature check admits only top-level C/D scalar functions without a
hidden context. It validates the formal parameter list even for imported
declarations that have no parameter `VarDeclaration`s. Existing AAPCS32 base
PCS/softfp argument layout is retained, including register-pair alignment and
8-byte public-call stack alignment. Arguments are evaluated into temporary homes
in source order before register/stack placement.

Ref/out/lazy parameters, ref-return, variadics, aggregate signatures, indirect
calls, nested functions, member functions and closures remain outside this slice.
Ordinary D `main` and CRT constructors/destructors are explicitly rejected because
their startup/lifecycle contracts are not represented. Disabled unittest bodies
are skipped; enabled unittests remain rejected by the existing driver gate.

No target-selection, ELF writer, runtime pin or instruction-layout change is part
of this step. General D global data, TLS, aggregate lowering, exceptions and
ModuleInfo lifecycle/import data retain their previous boundaries.

## Independent qualification

`verify.py` runs the new lane as part of the existing Android ARM32 suite.

| Check | Evidence |
|---|---|
| Exact symbol identity | Fixed expected names for overloads, identically named functions in different modules, pointer backreferences, attributes and `pragma(mangle)`; expected names were also checked against pinned upstream DMD 2.113.0 with `-m32` |
| Separate compilation | `ordinary_d_linkage.d`, `ordinary_d_peer.d` and `ordinary_d_calls.d` are compiled separately, using actual D imports; defined symbols and external call relocations are checked before linking |
| Definition ABI | Handwritten A32 calls emitted D functions and checks integer, pointer, float, double and 64-bit argument/results, register holes and stack arguments |
| Caller ABI | Emitted D callers invoke independently assembled D-symbol callees; the assembly checks argument values and stack alignment |
| C interoperability | An `extern(C)` D wrapper calls a D function; D calls an independently assembled C-symbol callee |
| Evaluation order | Five side-effecting nested calls must execute once each, left to right, producing `12345` |
| Module registration | The assembly oracle checks three ModuleInfo pointers, one retained COMDAT registration thunk, descriptor contents and unregister invocation |
| Unsupported constructs | Fourteen cases must pass frontend semantics, fail at the intended backend diagnostic and remove a deliberately stale output object; disabled unittest succeeds and enabled unittest is recorded as an earlier driver refusal |
| False-pass controls | Two mutated inputs must make a separate outer verifier process fail at the intended symbol/execution stage |

The assembly contains sixteen scalar/call checks plus registration checks. It
masks failed-check exit status to a byte and maps zero to 255, so a corrupted
stage register cannot turn a failed comparison into successful process exit.

The zero-result mutant must reach execution and fail with status 1. The wrong
symbol mutant must fail symbol validation. An unrelated compilation, linking or
environment error cannot satisfy either mutation check.

The verifier emits `ordinary-d-linkage-provenance.txt`,
`ordinary-d-linkage-mutants.tsv`, `ordinary-d-boundary.tsv`, per-object `readelf`
reports, the compiled objects and the executable oracle. The existing DMD
baseline workflow uploads these under an artifact name containing the exact PR
head. The boundary table has nineteen rows: four supported constructs, fourteen
backend rejections and one driver rejection.

## Initial local validation receipt

Qualification base: `aba7362c6fa6e4079c91ad443934b3efd74b6609` (`dmd-upstream`).
The sole compiler-source change is `compiler/src/dmd/glue/arm32.d`, Git blob
`c0c0acddb70f3029ae63f6ba353ee7e887fd8a58`.
Owned source provenance remains DMD v2.113.0 as recorded in `SOURCE.lock`.

The baseline and candidate were built in separate worktrees with the same
SHA-verified DMD 2.113.0 bootstrap archive:
`b342ab8bd40cc0c46407692b31d7cd69661ff01da686234f426949e881727294`.
Local validation used Ubuntu 24.04 x86_64, Clang/LLD 18.1.3, QEMU 8.2.2 and the
bootstrap archive's matching druntime import declarations.

| Result | Status |
|---|---|
| Owned baseline and candidate compiler builds | PASS |
| Unchanged ordinary-D identity fixture on baseline | Rejected by the old C-linkage gate, as expected |
| Candidate Android ARM32 verifier, including scalar D linkage and both outer mutants | PASS |
| Existing C scalar, PIC/global, arithmetic, cast and softfp regressions | PASS |
| Existing ARMv7 NEON float4 FFT execution | PASS |
| Existing AArch64 floating-comparison/NaN verifier | PASS |
| Baseline/candidate C scalar, NEON FFT and previous ordinary-D C-linkage object bytes | Identical for all three objects |
| Independent compiler and oracle source review | No unresolved blocker |
| Android druntime link | NOT_QUALIFIED |
| Physical-device execution | NOT_RUN |

Local candidate compiler SHA-256:
`4f7fdafb74b933553ddd0025dc3f3780d97a84c29933320663f8fbbc9267cfde`.
Local baseline compiler SHA-256:
`cd68aa4a058cd5774edb7c771d8259d8921b7d467365ee1ae841df010471db87`.
Local three-module executable SHA-256:
`cd79b9edcd5708f0b26d7866bca6fbffe62b46692aedbfaf5df1f5d1638c9021`.
These identify this local validation; hosted builds record their own compiler
and output digests for the checked-out head.

## Remaining runtime boundary

Execution here is a **QEMU Linux-syscall oracle** around Android-target objects.
The assembly `_d_dso_registry` implementation is a **test-only ABI oracle** and
does not implement druntime. It is not emitted into compiler-produced objects.
The existing PIC shared-object check deliberately leaves that symbol unresolved.

An Android runtime link still needs `_d_dso_registry` and its dependencies from
matching Android ARM32 druntime. Broader runtime compilation also needs the
remaining aggregate, TLS, exception and lifecycle lowering. This receipt makes
no Android startup, Phobos or physical-device acceptance claim. The pre-existing
host Linux full-runtime workflow remains a separate regression gate.
