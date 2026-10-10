# Android ARM32 ordinary-D object boundary

Scalar-linkage qualification base: `dmd-upstream` at
`aba7362c6fa6e4079c91ad443934b3efd74b6609`.
Owned source: DMD v2.113.0 snapshot recorded in `dmd/SOURCE.lock`.
Target: `armv7a-linux-androideabi21`, compile-only, **without `-betterC`**.
The added scalar function/call boundary and its execution evidence are detailed
in [D_LINKAGE_BOUNDARY.md](D_LINKAGE_BOUNDARY.md).
The subsequent scalar-memory repair, full-width pointer execution and global
alignment checks are in [SCALAR_MEMORY_BOUNDARY.md](SCALAR_MEMORY_BOUNDARY.md).

## Qualification receipt

These results were obtained with the owned compiler built using the SHA-verified
DMD 2.113.0 bootstrap (`b342ab8bd40cc0c46407692b31d7cd69661ff01da686234f426949e881727294`).
The same ladder is part of `verify.py`; it emits `ordinary-d-boundary.tsv`, an
explicit `readelf` report, object/compiler digests, and the objects in CI.
Frontend success is independently tested with `-c -o-`; backend failures must
report `A32 backend:` and remove a deliberately pre-existing output object.

| Normal-D construct | Parse/semantic | ARM32 admission | ELF object | Runtime references emitted | Support / next blocker |
|---|---|---|---|---|---|
| Empty module | PASS | Reached | PASS | Defined standalone ModuleInfo; `minfo` pointer; strong undefined `_d_dso_registry`; hidden undefined `__start_minfo`, `__stop_minfo` | Object supported; matching Android ARM32 druntime body needed |
| Exported `extern(C)` scalar function | PASS | Reached | PASS | Same module metadata and registration requirements | Object supported; matching Android ARM32 druntime body needed |
| Default D-linkage scalar function and direct call | PASS | Reached | PASS | Exact D function symbols/call relocations; ModuleInfo and registration requirements | Qualified top-level scalar slice; matching Android ARM32 druntime body still needed |
| Scalar pointer loads/stores and indexing; byte-sized bool globals | PASS | Reached | PASS | ModuleInfo and registration requirements; explicitly declared callback/data dependencies | Qualified memory widths, assignment results, adjacent-memory preservation and global alignment; see scalar-memory receipt |
| Runtime `assert` in a C-linkage function | PASS | Reached, rejected | None; stale output removed | None emitted; lowering would require the assertion entrypoint and a D source-file slice | D slice/source data and assertion-call lowering missing |
| Static module constructor | PASS | Reached, rejected | None; stale output removed | None emitted; ModuleInfo lifecycle callback required | Exact callback/import ModuleInfo fields and relocations missing |
| `ref`/`out`/`lazy` arguments, ref-return, variadics, aggregate result, nested call, D `main`, CRT lifecycle functions | PASS | Reached, rejected | None; stale output removed | None emitted | Unsupported signature, context, startup or lifecycle lowering; fourteen backend controls in the full boundary ladder |
| Disabled `unittest` declaration | PASS | Reached | PASS | Standalone ModuleInfo and registration requirements | Disabled body skipped; no unittest execution qualified |
| Enabled `unittest` (`-unittest`) | Not reached | Not reached; driver rejects | None emitted | None emitted | Existing driver instrumentation gate; no frontend/backend success claimed |

The successful objects are ELF32 little-endian ET_REL/EM_ARM/EABI5, A32, with
AAPCS32 base PCS/softfp, 32-bit pointers, and 8-byte public-call stack alignment.
The ordinary scalar fixture independently checks Android, ARM, ARM_SoftFP,
CRuntime_Bionic, D_ModuleInfo and pointer/size_t widths. No target/ABI selection
code was changed, and no device-specific ABI was introduced.

The ELF writer emits DMD's `CompilerDSOData` v1 registration contract: a mutable
32-bit COMDAT DSO slot, a PIC A32 thunk, and pointers to the thunk in grouped
init/fini arrays. Each module's `minfo` pointer is outside the COMDAT group.
`R_ARM_REL32` address literals avoid dynamic text relocations; the external
registry call is `R_ARM_CALL`. The two-module QEMU ABI oracle verifies one
registration thunk, both module pointers, descriptor fields, stack alignment,
scalar result, and unregister invocation. A `-shared -z text` link independently
checks PIC admissibility and keeps `_d_dso_registry` unresolved.

The oracle's registry implementation is **test-only**, not druntime, and is not
included in the emitted compiler object. There is no Android druntime link,
Phobos build, or physical-device execution claim. Host Linux full-D qualification
is a separate fact and is not evidence of Android full-D runtime support.

## Admission-rule audit

Only `main.d` explicitly required `-betterC`; the custom AST/object path also
implicitly depended on its runtime suppression. The following covers that gate
and every family of restrictions in the ARM32 path; none was blanket-disabled.

| Rule / location | Classification and disposition |
|---|---|
| `main.d`: mandatory `-betterC` | Previously protected missing ModuleInfo/DSO emission, not merely stale. Replaced only after adding standalone metadata and registration. Existing scalar A32 lowering is reused unchanged. |
| `main.d`: no linking, libraries, `-run` | No qualified Android linker/runtime integration; retain compile-only boundary. |
| `main.d`: no coverage, profiling, GC profiling, unit tests | Runtime instrumentation and its extra functions/data are not lowered; retain. Ordinary unit-test lifecycle data is likewise not represented. |
| `main.d`: no debug/debug-reference output | Custom ELF writer lacks debug emission; retain, independent of runtime availability. |
| `glue/package.d`: libraries, split objects, library modules, combined multi-module object | Custom object orchestration/packaging missing; retain. Separate ordinary-D objects can be linked by the external test linker. |
| `glue/arm32.d`: function linkage, direct calls and symbol names | Admit module-level C or D scalar functions without a hidden context. Definitions and direct-call relocations share DMD's exact function mangler for D linkage; the existing C symbol rules remain. Methods, nested functions/closures, D `main`, CRT lifecycle functions and other linkages remain rejected. Global data retains its C-linkage boundary. |
| Function/call checks: scalar signatures, no variadics/ref-return/ref/out/lazy, at most 64 arguments | General AAPCS32 classification and D parameter semantics missing; retain. `target.d:toArgTypes` still declines aggregate classification. |
| Scalar/float4 type and operator checks, conversions, address/index/memory checks | Memory widths one/four/eight are qualified for bool and existing scalars; float4 dereference remains supported. Stack-local addresses, function values/indirect calls, other narrow types, aggregate/vector indexing, unsupported vector operations and arbitrary symbol offsets remain rejected. Not a druntime-only obstacle. |
| Locals: no static/by-reference locals, captured or uninitialised homes, expression initializers only | Storage/aliasing/closure/initializer lowering missing; retain. Frame, nesting, duplicate and literal-placement bounds are compiler safety checks, not BetterC policy. |
| Statements/expressions: supported loops only; no unsupported allocation/assert/exception operations | Some need runtime calls that could remain unresolved, but also need D slices, TypeInfo/ClassInfo, allocation/exception lowering or unwind representation. External references alone cannot repair absent lowering; retain fail-closed dispatch. |
| Global data: non-TLS shared/__gshared C-linkage scalar constants only; no const/immutable/vector data | Scalar storage uses its actual one/four/eight-byte size and honors declaration/section alignment. TLS, read-only/aggregate data and general data relocations remain missing; retain. |
| Member dispatch: only handled attributes, functions, scalar variables, imports, aliases, enums and static asserts | Classes/structs/templates/other declarations require general metadata/data emission; retain rejection rather than quietly dropping them. |
| Module lifecycle/import requirements (`needmoduleinfo`) | Standalone layout is now represented; lifecycle/import fields and callbacks are not. New explicit rejection prevents a truncated ModuleInfo record. Missing druntime ModuleInfo interface also fails closed. |
| `dmdparams.d` target restriction, `target.d` ABI/vector/stack rules | Android ARMv7/API21+ only, Bionic, base PCS, pointer/real sizes, float4 limits and stack alignment remain unchanged; these are target contracts, not BetterC assumptions. |

## Exact next boundary

For the successful standalone objects, the linker can supply the hidden
`__start_minfo` / `__stop_minfo` brackets. The missing runtime provider is
**`_d_dso_registry` from matching Android ARM32 druntime** (and its runtime
dependencies). No complete runtime body is compiled or qualified here. Compiling
broader druntime modules is additionally blocked by the retained non-scalar D,
aggregate/TLS/exception lowering and lifecycle/import ModuleInfo boundaries.
Providing an empty registry stub would not qualify a runtime link.

The real matching provider was subsequently probed directly: compilation first
fails in frontend imports because the runtime lacks DigitalMars ARM
`c_long_double` and the compiler selects the wrong ARM `va_list` type. Those
specific compatibility failures, source identities and the later source-observed
backend dependencies are recorded in the scalar-memory receipt. No runtime stub
or compiler-identity substitution was used to bypass them.

Existing BetterC scalar and NEON fixtures/checks/harnesses are unchanged and pass
the same ELF, external-link and QEMU regressions.
