# Linux-kernel construct corpus for compiler archaeology

Research pass: 2026-09-29

This replaces the initial idea of tracing one synthetic counted loop through
every compiler. The Linux kernel supplies a much richer set of real C
constructs, and many already correspond closely to constructs used by ICK,
Wegert, and Pauli.

Kernel source inspected at commit:

`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`

The kernel is a research corpus here, not ICK source. Do not copy kernel code
into ICK merely to construct compiler tests; write reduced examples whose
semantics are independently stated.

> **Method:** start from the exact production source sites. Small reductions are
> allowed only after the source pair is recorded; a reduction must never replace
> the archaeology or silently change the compiler question.

## Selection rule

A construct qualifies for this corpus when:

1. it already occurs in ICK/Wegert/Pauli code, or is an immediate extension of
   a pattern already used there;
2. the kernel contains a clean production example;
3. the construct exposes a compiler seam worth tracing: parsing, type
   semantics, constant folding, lowering, optimization, ABI/layout, or target
   code generation.

The goal is not to imitate kernel coding style. The goal is to use mature,
real-world C as a source of compiler questions.

---

## 1. Small wrapper structs

### Our code

ICK uses distinct wrapper structs for low-precision values and finite geometry:

- `ick/include/ick/imprecise.h`: `Float16`, `E4M3`, `E5M2`, `E3M2`,
  `E5M3`;
- `ick/include/ick/circle.h`: `Circle96`, `Rotation96`,
  `Reflection96`, `Tangent96`.

These deliberately create distinct C types around byte/word payloads.

### Kernel analogue

`include/linux/types.h` defines `atomic_t` as a struct wrapping an integer
counter rather than a typedef of plain `int`.

### Compiler questions

- When does a one-field struct remain in registers?
- When is it ABI-identical to its scalar payload, and when is it not?
- How are copies, returns, and arguments lowered?
- Does alias analysis retain useful type distinction?
- Can optimization erase the wrapper without erasing the language-level type?

This is extremely close to ICK's imprecise types.

---

## 2. `static inline` value operations

### Our code

`ick/include/ick/imprecise.h` and `ick/include/ick/circle.h` contain many
small `static inline` accessors and arithmetic/geometric operations.

Wegert has the same pattern in `code/factor_drag.h`.

Pauli uses it in `runtime/ick_complex_f64.h`.

### Kernel analogues

- `mm/cma.h`: small arithmetic/accessor helpers;
- `fs/bfs/bfs.h`: inline conversion from embedded `struct inode` to a
  containing filesystem-specific structure;
- `mm/memfd.c`: tiny bitmask predicates.

### Compiler questions

- At what stage is inline eligibility represented?
- What happens at `-O0`, `-O1`, `-O2`, and size-oriented modes?
- Does the compiler preserve debug visibility?
- Does a wrapper-struct argument inhibit scalar replacement?

---

## 3. Struct/union layout

### Our code

ICK uses unions for bit reinterpretation in `ick/include/ick/imprecise.h`,
including float/integer views.

Wegert and Pauli use ordinary state structs extensively.

### Kernel analogues

- `net/smc/smc.h`: union views over protocol headers;
- `io_uring/rw.h`: unions for mutually exclusive storage;
- `block/t10-pi.c`: on-stack union storage;
- `arch/csky/lib/string.c`: unions of pointer representations.

### Compiler questions

- Exact object layout and alignment;
- active-member/alias assumptions;
- loads/stores generated for union views;
- scalar replacement of aggregates;
- target endianness effects.

The kernel cannot supply a floating-point analogue to ICK's float/integer
bit-view because ordinary kernel code avoids floating point, but the union
mechanics are still directly useful.

---

## 4. Compile-time layout assertions

### Our code

ICK uses `_Static_assert` for assumptions such as byte size, binary32 shape,
and complex object size.

### Kernel analogues

- `crypto/md5.c` and `crypto/sha1.c`: assert equal sizes and member offsets
  across related state structures;
- `mm/slab.h`: assert structure-size and alignment relationships;
- `fs/qnx4/qnx4.h`: `BUILD_BUG_ON` for matching member offsets;
- `arch/x86/hyperv/hv_crash.c`: exact ABI/layout offset assertions.

### Compiler questions

- Constant-expression evaluation;
- `sizeof`, `offsetof`, alignment and target data layout;
- diagnostics for failed assertions;
- whether target-layout reasoning lives in frontend or backend machinery.

This is directly relevant to ICK's ABI and low-precision layout gates.

---

## 5. Attributes affecting ABI/layout

### Our code

ICK/Wegert use GNU `__attribute__`, notably symbol visibility and
no-inline/no-IPA test controls.

### Kernel analogues

- `fs/isofs/rock.h`: packed structures;
- `fs/btrfs/send.h`: packed wire-format structures;
- `include/net/flow.h`: explicit alignment;
- many network and device headers use `__packed`.

### Compiler questions

- Parsing GNU attributes;
- propagation through type construction;
- layout changes;
- unaligned load/store generation;
- ELF visibility versus object-layout attributes.

This gives a good split between frontend attribute semantics and target codegen.

---

## 6. `switch` lowering

### Our code

- `ick/source/gcc/tree-complex.cc`;
- Wegert input/event and glyph code;
- Pauli Android command and orbital-family dispatch.

### Kernel analogues

- `fs/nsfs.c`: ioctl-command dispatch;
- `lib/audit.c`: syscall classification.

### Compiler questions

- linear comparisons versus jump tables versus decision trees;
- density heuristics;
- constant folding of cases;
- target-specific branch/jump-table materialization;
- effect of profile/likely information.

This should replace an artificial switch microbenchmark.

---

## 7. Arrays, pointer + length, and `memcpy`

### Our code

- Wegert offscreen image row swapping;
- Pauli complex physical-slot conversion;
- ICK complex-layout tests;
- Android boundary functions using explicit scalar/array ABIs.

### Kernel analogues

- `lib/string.c`: simple generic `memcpy`;
- `arch/nios2/lib/memcpy.c`: target implementation;
- `kernel/module/main.c`: repeated per-CPU copies;
- `drivers/xen/efi.c`: layout assertion followed by structure copy.

### Compiler questions

- recognition of library/builtin operations;
- expansion inline versus libc/libcall;
- vectorization and alignment assumptions;
- alias analysis;
- target-specific replacement.

This is one of the best seams for comparing tiny compilers with GCC/Clang.

---

## 8. Counted loops and macro-generated iteration

### Our code

ICK qualification code and Wegert rendering/manipulation code already contain
ordinary counted loops.

### Kernel analogues

- `lib/lwq.c`: ordinary `for` loops and macro-generated safe iteration;
- `lib/plist.c`: counted array iteration;
- `kernel/module/main.c`: `for_each_possible_cpu`;
- `fs/pnode.c`: list iteration macros.

### Compiler questions

Trace both:

1. an ordinary `for (i = 0; i < n; ++i)`; and
2. a macro-expanded iterator.

That exposes preprocessing as well as loop lowering and optimization.

---

## 9. Bit fields expressed as masks/shifts

### Our code

ICK's compact numeric encodings and Circle96-style finite representations make
bit extraction and packing central operations even when written through helper
functions rather than C bitfield syntax.

### Kernel analogues

- `drivers/pci/rebar.c`: `FIELD_GET`;
- `net/dsa/tag_qca.c`: mask extraction plus validity check;
- kernel bit operations throughout `lib/find_bit.c`.

### Compiler questions

- constant mask folding;
- shift/mask recognition;
- extraction instructions;
- signed versus unsigned semantics;
- endianness-independent source versus target operations.

This should be a major ICK case because E3M2/E4M3/E5M2 encoding depends on it.

---

## 10. Branch prediction annotations

### Our code

Current application code mostly uses ordinary branches, but ICK inherits GCC's
branch-probability machinery and the question matters for rendering/event loops.

### Kernel analogues

- `fs/fs_pin.c`: `likely()`;
- `io_uring/tw.h`: tiny inline predicate wrapped in `likely()`;
- `net/dsa/tag_qca.c`: `unlikely()` validation branch.

### Compiler questions

- how `likely/unlikely` becomes branch probability metadata;
- whether small compilers ignore it;
- how it affects layout and code generation;
- whether generated code changes without changing semantics.

---

## 11. `typeof`, `container_of`, and typed macros

### Our code

ICK is GCC-derived and therefore necessarily encounters GNU C extensions.
Our own code already relies on GNU attributes and builtins; typed macro
machinery is the next natural real-world GNU-C stress case.

### Kernel analogues

- `fs/bfs/bfs.h`: `container_of`;
- `security/tomoyo/gc.c`: `container_of(..., typeof(*ptr), ...)`;
- `kernel/sched/swait.c`: `typeof` with list helpers.

### Compiler questions

- GNU `typeof` parsing/type construction;
- `offsetof` constant expressions;
- macro expansion plus type checking;
- pointer arithmetic lowering;
- diagnostics when container/member types disagree.

This will sharply separate compilers that aim for GCC compatibility from
strictly smaller C implementations.

---

## 12. Atomics and single-access semantics

### Our code

ICK's current application examples do not yet rely heavily on atomics, but the
compiler foundation contains atomic types and Android/event-loop work will
eventually require concurrency semantics.

### Kernel analogues

- `include/linux/types.h`: `atomic_t`;
- `lib/llist.c`: `READ_ONCE` plus compare/exchange;
- `lib/errseq.c`: `READ_ONCE`;
- `include/net/sch_generic.h`: per-CPU values read through `READ_ONCE`.

### Compiler questions

- volatile-like single-access semantics versus C atomics;
- builtin lowering;
- memory-order representation;
- target atomic instructions and barriers.

This belongs later in the trace suite because tiny compilers vary widely here.

---

## 13. Flexible arrays and size-safe allocation

### Our code

Not yet central, but directly relevant to compact filesystem-first/runtime
structures and future variable-sized compiler data.

### Kernel analogues

- `include/linux/stddef.h`: `DECLARE_FLEX_ARRAY`;
- `include/linux/overflow.h`: helpers around trailing flexible arrays;
- `net/xdp/xsk_queue.c`: `struct_size` calculations.

### Compiler questions

- flexible-array layout;
- `sizeof` rules;
- bounds/sanitizer behavior;
- overflow-safe size calculations.

Useful as a later standards/layout case.

---

## 14. Designated initializers

### Our code

ICK's union bit views already use designated initialization:

`union { float value; ick_u32 bits; } view = { .value = value };`

### Kernel analogues

The kernel deliberately uses and enforces designated initializers in many
interfaces. `scripts/Makefile.warn` even enables a designated-initializer
diagnostic for marked structures.

### Compiler questions

- initializer parsing;
- zero initialization of omitted members;
- union-member selection;
- constant object emission;
- diagnostics and extension behavior.

This is an excellent direct ICK-to-kernel match.

---

# Constructs the kernel does not cover well for us

The kernel is not enough by itself.

## Floating point

Normal kernel code generally avoids ordinary floating-point computation.
Wegert, Pauli, and ICK's imprecise types depend heavily on `float` and
`double`.

Use our own application code plus numerical C projects for these cases.

## C `_Complex`

ICK's polar physical complex representation is one of the most distinctive
parts of our work. The Linux kernel is not a useful corpus for `_Complex`.

Use ICK/Wegert/Pauli directly.

## GPU/shader boundaries

Kernel source can teach ABI, layout, bit operations and target-specific
lowering, but not the GLES/shader compilation boundary we care about.

Use Wegert/Pauli and later GPU compiler sources.

---

# Revised archaeology order

Do not trace every compiler through every construct immediately.

Start with six cases that already matter directly to our code:

1. one-field wrapper struct;
2. `static inline` operation on that wrapper;
3. union/designated-initializer bit reinterpretation;
4. compile-time `sizeof`/layout assertion;
5. mask/shift field extraction;
6. pointer + length loop with `memcpy`.

Then add:

7. `switch`;
8. macro iterator;
9. GNU `typeof` + `container_of`;
10. packed/aligned struct;
11. atomics/single-access semantics;
12. flexible array.

Keep two non-kernel ICK-specific tracks beside this corpus:

- floating/low-precision arithmetic;
- `_Complex` polar representation.

For each compiler, record:

- source file/function where parsing occurs;
- source representation after parsing;
- each IR or lowering stage involved;
- whether the construct is optimized specially;
- target-specific seam;
- whether the compiler supports the construct at all;
- approximate implementation surface touched.

That gives us a real architectural comparison rather than a collection of
benchmark anecdotes.
