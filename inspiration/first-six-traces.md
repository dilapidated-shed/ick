# First six paired source traces

Corrected source-archeology pass: 2026-09-29

This document starts from **actual production source sites**, not invented
microexamples. The small files under `fixtures/` are secondary reductions for
later executable comparison. They must not replace the source archaeology.

## Source pins

- Linux kernel: `torvalds/linux@72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`
- ICK source as inspected on `inspiration` before this correction:
  `dilapidated-shed/ick@33058955cc3eb57140cc9c9fca09eaf4df78aed3`
- Wegert: `isomorphismes/wegert@296fbc6e916341d680c6c473bb490e6ce41b18d8`
- Pauli: `isomorphismes/pauli@c1e8a687951d8fbcba2003dccbf5b43c3a7461e3`

Reference compiler pins remain those recorded in
[`README.md`](README.md).

The question for every case is:

> What does a mature real-world C construct used in the kernel look like beside
> the corresponding construct already used in our code, and where does each
> reference compiler represent or transform it?

---

# 1. One-field wrapper types

## Actual kernel site

`include/linux/types.h` defines `atomic_t` as a structure containing one
integer counter. The field carries an explicit alignment requirement.

This is not merely a typedef. C's type system distinguishes the wrapper from
plain `int`, while the compiler still has opportunities to pass, return, copy,
or scalarize it efficiently.

## Actual ICK sites

`ick/include/ick/imprecise.h` defines one-field storage wrappers:

- `Float16` around a 16-bit payload;
- `E4M3`, `E5M2`, `E3M2`, and `E5M3` around byte payloads.

`ick/include/ick/circle.h` uses the same technique for `Circle96`,
`Rotation96`, `Reflection96`, and `Tangent96`.

ICK then asserts the intended physical sizes. These types deliberately preserve
semantic distinctions that a raw byte typedef would erase.

## What to trace

This is the real pair:

`atomic_t`  ↔  `E4M3` / `Circle96`

Trace:

1. parsing of a one-field record;
2. target layout and alignment;
3. function argument and return ABI;
4. aggregate copies;
5. scalar replacement/registerization;
6. whether distinct source types remain useful to alias/type analysis after
   the physical wrapper disappears.

## Compiler source seams

- **GCC / ICK** — `gcc/c/c-parser.cc:c_parser_struct_or_union_specifier`;
  `gcc/stor-layout.cc:layout_type`; later TREE/GIMPLE/ABI machinery.
- **Clang / LLVM** — `clang/lib/Parse/ParseDecl.cpp:ParseStructUnionBody`;
  `clang/lib/AST/RecordLayoutBuilder.cpp`; LLVM later scalarizes.
- **TinyCC** — `tccgen.c:struct_decl`, `type_size`; short path into target
  code generation.
- **chibicc** — `parse.c:struct_union_decl` / `struct_decl`; typed AST then
  direct x86-64 codegen.
- **cproc / QBE** — `decl.c:structdecl`; `cc.h` member representation;
  `qbe.c` crosses the frontend/backend boundary.
- **lacc** — `src/parser/typetree.c`; parser constructs three-address CFG
  rather than retaining a full AST.
- **8cc** — `parse.c:read_rectype_def`,
  `update_struct_offset`; direct x86-64 path.
- **cparser / libFirm** — compound types in `src/ast/type*.h`;
  `src/firm/ast2firm.c`; Firm graph/backend thereafter.
- **CompCert** — composite layout is part of the formal type semantics;
  `cfrontend/Ctypes.v:sizeof_composite`.
- **PCC** — `cc/ccom/cgram.y`; `cc/ccom/pftn.c:tsize`; machine-independent
  pass 2 then target backend.
- **slimcc** — `parse.c:struct_union_decl`; chibicc-derived typed AST with
  additional codegen optimization.
- **c4** — no struct support; it serves as a language-frontier control.

The executable reduction should contain both an aligned integer wrapper and a
byte wrapper. A generic `box8` by itself misses half of the comparison.

---

# 2. Small `static inline` operations

## Actual kernel site

`mm/memfd.c:is_write_sealed` is a tiny `static inline` predicate over a
bitmask.

The function matters because it exercises two distinct compiler obligations:

- C `inline` linkage/emission semantics;
- optional optimization-time call substitution.

## Actual ICK site

`ick/include/ick/circle.h:rotate96` is a small `static inline` operation on
wrapper types. It adds two byte-backed values, performs one bounded correction,
and returns a distinct wrapper type.

Other nearby ICK examples include `circle96_code_is_canonical`,
`third_sector`, and the FP8 arithmetic helpers in
`ick/include/ick/imprecise.h`.

## What to trace

The real pair is:

`is_write_sealed`  ↔  `rotate96`

The useful question is not "does the compiler support `inline`?" Record
separately:

1. whether the source is accepted;
2. whether C inline/linkage rules are implemented correctly;
3. whether an unused local definition is omitted;
4. whether a call remains in generated code;
5. whether wrapper construction disappears after inlining/scalarization.

## Important result already visible in source

Several small compilers implement **inline-definition semantics without an
optimization inliner**:

- TinyCC stores inline bodies as token lists and emits referenced definitions
  late.
- chibicc tracks inline functions and liveness; its README explicitly says it
  has no optimization pass.
- 8cc accepts `inline` but ignores it in declaration-specifier handling.
- slimcc explicitly says it currently does not inline functions.
- cproc records C11 inline-definition state; no body-substitution pass was
  found in the pinned frontend.
- lacc records/defer-emits inline definitions; no separate call-site
  substitution pass was found in the inspected source.

By contrast GCC, LLVM, libFirm, CompCert, and PCC have explicit optimization
inlining machinery.

That distinction should remain a first-class result of this comparison.

---

# 3. Union representation + designated initialization

## Actual kernel site

`arch/csky/lib/string.c` defines pointer-view unions used by its `memcpy`
implementation. A union object is initialized through a designated member and
then accessed through byte-pointer, word-pointer, and integer-address views.

This is real production use of:

- union representation;
- designated initialization;
- alternate views of the same stored bits;
- alignment-sensitive code generation.

## Actual ICK site

`ick/include/ick/imprecise.h` contains:

- `ick_float_bits`: initialize the float member of a local union, return the
  integer-bits member;
- `ick_float_from_bits`: initialize the integer member, return the float
  member.

The source shape is strikingly close to the kernel example even though the
represented domains differ.

## What to trace

The real pair is:

C-SKY `memcpy` pointer-view unions  ↔  ICK float/integer bit-view union

Trace:

1. designated-initializer parsing;
2. union member layout;
3. source-language rules for alternate-member reads;
4. whether the frontend preserves a union operation or immediately reduces it
   to loads/stores/bitcasts;
5. whether optimization accidentally turns the operation into a numeric
   conversion rather than an object-representation reinterpretation;
6. target endianness and alignment assumptions.

## Compiler source seams

- GCC: initializer/designator machinery in `gcc/c/c-parser.cc` and
  `gcc/c/c-typeck.cc:set_designator`; generic union layout thereafter.
- Clang: `DesignatedInitExpr` preserves the written designator;
  `SemaInit.cpp:InitListChecker` builds the semantic initializer form.
- TinyCC: `tccgen.c:decl_designator`.
- chibicc: struct/array designators plus `union_initializer` in `parse.c`.
- cproc: `init.c:designator`.
- lacc: initializer handling under `src/parser/initializer.c`.
- 8cc: `read_initializer_list(..., designated)`.
- cparser: first-class `designator_t` AST nodes before Firm lowering.
- CompCert: explicit `Init_struct` and `Init_union` constructors in its
  parser representation and verified initializer translation.
- PCC: initializer stack machinery in `cc/ccom/init.c`.
- slimcc: designated/aggregate initializer machinery in `parse.c`.
- c4: no union/designated aggregate support.

The previous reduction deliberately avoided alternate-member interpretation.
That removed the most interesting part. The corrected reduction now models the
ICK direction explicitly; the kernel source remains the production reference.

---

# 4. Compile-time layout contracts

## Actual kernel site

`crypto/md5.c` uses compile-time assertions to require two MD5 state
structures to agree in:

- total size;
- the offset of the state/hash field;
- the offset of the byte-count field;
- the offset of the block buffer.

The code then relies on those layout facts when copying state.

This is stronger than a generic "struct is at least N bytes" check: the
program establishes a binary-layout contract between independently named
types.

## Actual ICK sites

`ick/include/ick/imprecise.h` asserts:

- byte width and binary32 assumptions;
- exact storage sizes for Float16 and the FP8/FP6 wrappers.

`ick/source/gcc/testsuite/gcc.dg/ick-complex-round.c` asserts that
`float _Complex` and `double _Complex` each occupy exactly two scalar slots
under ICK's physical representation.

Pauli independently repeats the double-complex two-slot contract in
`runtime/ick_complex_f64.h`.

## What to trace

The real comparison is:

kernel cross-structure `sizeof` + `offsetof` contracts
↔
ICK exact storage/slot assertions

Trace:

1. parsing of `_Static_assert`;
2. constant evaluation of `sizeof` and `offsetof`;
3. where target data layout enters the calculation;
4. diagnostic quality when a contract fails;
5. whether the compiler exposes enough layout information to build stronger ICK
   ABI tests.

A useful follow-on for ICK is to adopt more **offset equality** assertions where
physical interfaces depend on member positions, not just total size.

The old reduction only checked minimum aggregate sizes. It missed the kernel
idea. The corrected reduction compares two independently named layouts with
`__builtin_offsetof`.

---

# 5. Bit-field extraction expressed as masks and shifts

## Actual kernel sites

`drivers/pci/rebar.c` uses `FIELD_GET` to extract packed fields from PCI
register words.

The implementation in `include/linux/bitfield.h` is important. The public
macro adds compile-time checks and type preservation; its core operation masks
the register and shifts by the mask's trailing-zero count.

So this case has **two levels**:

1. the real GNU-C surface: statement expressions, `typeof`, `_Generic`,
   builtins, and compile-time checks;
2. the core mask/shift operation the optimizer ultimately sees.

## Actual ICK sites

`ick/include/ick/imprecise.h` performs exactly this kind of work in the
low-precision codecs:

- E4M3 exponent: shift by 3 and mask by 4 bits;
- E5M2 exponent: shift by 2 and mask by 5 bits;
- E3M2 exponent: shift by 2 and mask by 3 bits;
- sign and mantissa extraction/reassembly use related fixed masks/shifts.

`ick/include/ick/circle.h` adds an especially small pair:
`third_sector` shifts `Circle96.code`; `position_within_third` masks it.

## What to trace

The real pair is:

kernel `FIELD_GET` / PCI register extraction
↔
ICK FP8/FP6 and Circle96 extraction

Run two compiler comparisons:

### A. Surface compatibility

Can the compiler accept a reduced `FIELD_GET`-style GNU-C macro containing
the same language mechanisms?

This identifies GCC-compatibility frontiers. A failure here says nothing yet
about shift/mask code quality.

### B. Core operation

Compile the direct fixed mask/shift expressions used by ICK.

Trace:

- integer promotions;
- signed/unsigned shift semantics;
- constant folding;
- combine/demanded-bit analysis;
- target extraction instructions or fused addressing/bitfield operations.

This split prevents a parser-extension failure from being mistaken for a
backend weakness.

GCC uses `LSHIFT_EXPR` / `RSHIFT_EXPR`, GIMPLE optimization, optabs and
target descriptions. Clang lowers `BO_Shl` / `BO_Shr` into LLVM IR.
chibicc reaches direct x86 shifts from `ND_SHL` / `ND_SHR`. libFirm keeps
`iro_Shl` / `iro_Shr` graph nodes and applies explicit algebraic rewrites.
CompCert keeps named shift operations through its verified IRs and target
selection. PCC already performs local shift strength reductions in pass 1.

---

# 6. Memory copy: implementation loop, ordinary call, compiler builtin

The previous synthetic copy test obscured the strongest comparison. Our real
sources already supply all three forms.

## Actual kernel implementation

`lib/string.c` contains the generic kernel `memcpy` implementation: an
ordinary byte-copy loop used when an architecture does not provide its own
implementation.

`arch/csky/lib/string.c` supplies a target-specific implementation that uses
alignment tests, pointer-view unions, wide copies, shifts, and a byte
remainder.

So the kernel alone shows:

generic C loop
→ architecture-specific C implementation

## Actual Wegert call site

`code/wegert_offscreen_gles.c` flips rendered image rows using three ordinary
`memcpy` calls with a runtime `row_bytes` length.

This is not an implementation of memcpy; it asks the compiler/libc boundary to
perform a variable-size block copy.

## Actual Pauli / ICK builtin site

`runtime/ick_complex_f64.h` builds ICK's physical `double _Complex` object
from two scalar slots with `__builtin_memcpy` and a compile-time
`sizeof value` length.

ICK's own complex tests also contain an explicit byte-copy helper specifically
to inspect physical object representation without depending on libc.

## The real comparison

This case is therefore not one fixture. It is a three-shape family:

1. **copy implementation** — kernel generic/arch `memcpy`;
2. **ordinary call** — Wegert row copying;
3. **compiler builtin / object representation copy** — Pauli/ICK complex
   construction.

Trace them separately.

## Compiler source seams

- **GCC / ICK** — `BUILT_IN_MEMCPY`; tree passes reason about string/block
  operations; `gcc/builtins.cc:expand_builtin_memcpy` chooses later
  expansion.
- **Clang / LLVM** — Clang emits LLVM memcpy intrinsics; LLVM has both
  `LoopIdiomRecognize` and `MemCpyOptimizer`; backend lowering decides
  inline operations versus calls.
- **TinyCC** — documents `__builtin_memcpy` as mapped to libc; much less
  optimizer machinery sits between source and call.
- **chibicc** — no memcpy builtin was found in the pinned source and no
  optimization pass exists; verify by compilation before making a compatibility
  claim.
- **cproc / QBE** — ordinary call/control-flow lowering crosses into QBE; no
  cproc memcpy builtin was found.
- **lacc** — keeps a `decl_memcpy` reference specifically for code generation
  while explicit loops live in its CFG.
- **8cc** — no memcpy builtin or optimizer pass found.
- **cparser / libFirm** — this is unusually interesting: Firm represents block
  copies as `CopyB`; target-aware lowering can expand small copies to
  loads/stores, preserve medium CopyBs, or turn large copies into memcpy.
- **CompCert** — `EF_memcpy(size, alignment)` is explicit in the IR;
  CSE models its effects and each backend expands it.
- **PCC** — has `__builtin_memcpy` and target aggregate-copy paths that may
  construct memcpy calls.
- **slimcc** — its Linux compatibility script currently rewrites
  `__builtin_memcpy` to ordinary `memcpy`, which is itself useful evidence
  about the feature boundary.
- **c4** — use only a c4-specific byte loop as a conceptual lower bound; do not
  distort the shared source case to fit c4.

One caution matters for the executable pass: compiling an implementation of
`memcpy` and compiling a call to `memcpy` are not equivalent experiments.
Compiler builtin/loop-idiom settings can even risk recognizing the
implementation loop as a memcpy operation. Record freestanding/builtin flags
explicitly.

---

# Cross-case architecture map

| compiler | source/semantic representation | optimization / lowering relevant to these six |
|---|---|---|
| GCC / ICK | C parser → TREE → GIMPLE | IPA inline, folding, string/block ops, optabs, target backend |
| Clang / LLVM | rich Clang AST/Sema → LLVM IR | LLVM inline, bit combines, loop idioms, memcpy optimizer, target backend |
| TinyCC | compact parser/value machinery | mostly local/direct target generation; libc-oriented memcpy |
| chibicc | typed AST | no optimization pass; direct x86-64 codegen |
| cproc | C semantic structures → QBE IL | QBE owns backend optimization/codegen |
| lacc | parser builds three-address CFG directly | small dataflow optimizer → x86-64 backend |
| 8cc | compact AST/IR-like nodes | no optimization pass; direct x86-64 |
| cparser/libFirm | C AST → Firm graph | graph optimization, inliner, CopyB lowering, target graph transforms |
| CompCert | explicit formally specified IR sequence | verified transformations; explicit memcpy/shift operations |
| PCC | C pass 1 → machine-independent pass 2 | local optimizer + retargetable backends |
| slimcc | chibicc-family typed AST | basic direct codegen optimization; no function inliner |
| c4 | tiny expression/VM instruction model | useful only where its language subset reaches the construct |

# What the corrected six actually let us ask

The paired sources produce better questions than the synthetic fixtures did:

- Does GCC's aggregate machinery buy anything measurable for one-byte semantic
  wrappers?
- Can an ICK wrapper disappear physically while remaining distinct
  semantically?
- How do compilers treat real union-based object-representation views?
- Can ICK strengthen layout contracts from total-size checks toward kernel-style
  offset compatibility checks?
- Which part of kernel `FIELD_GET` cost belongs to GNU-C compatibility and
  which part belongs to mask/shift optimization?
- How differently do compilers represent a copy loop, an ordinary memcpy call,
  and a compiler builtin?
- Does libFirm's explicit `CopyB` or CompCert's explicit
  `EF_memcpy(size, alignment)` suggest a clearer ICK internal seam?
- Which GCC layers earn their cost on the actual constructs ICK uses?

# Executable reductions

The files under `fixtures/` remain useful only after the source comparison.
They are independently written reductions, not substitutes for the kernel or
our application sources.

For every fixture result, the eventual report must point back to the exact
production pair in this document. If a reduction stops resembling the source
construct that motivated it, change the reduction rather than changing the
question.
