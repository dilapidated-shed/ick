# Icky D community prior art ledger

Status: research notes only, 2026-09-30.

This note records projects worth learning from before extending **Icky D**. It
does not choose an implementation and does not authorize copying code merely
because a project is useful.

Naming in this note is deliberate:

- **Icky D** is the D compiler line discussed here.
- **Icky C** is the C line.
- **IckY** is the yacc/parser line.
- **iCk** is the GCC-derived C compiler line.

The current experimental DMD work happens to live on `dmd*` branches of the
same repository as iCk. That repository layout must not be confused with the
compiler names.

The existing D/GPU surveys remain useful and are not repeated in full:

- [D -> GPU prior art](d-gpu-prior-art.md)
- [Expanded D GPU research](d-gpu-expanded-research.md)

The purpose of this file is broader: DMD/Mars, Android and the D runtime,
ARMv7/AArch64, DEX/ART, EGL/GLES, the two physical GPU families we actually
have, and compiler projects that solve analogous lowering problems.

## How to use this ledger

For every source, distinguish three kinds of value.

1. **Implementation source**: code may be reusable after checking provenance,
   license and fit.
2. **Design/test source**: architecture, algorithms and tests may transfer even
   when code should not.
3. **Oracle/spec source**: use the project to generate expected behavior or
   inspect target output; do not make its implementation our specification.

The highest-value rule is to reuse existing D semantics rather than reconstruct
them. The official DMD frontend, druntime, Phobos, LDC and GDC collectively
contain far more knowledge about D than a new backend should invent.

---

# 1. D compiler family

## DMD

Repository: <https://github.com/dlang/dmd>

Why it matters:

- this is the frontend and Mars backend Icky D is extending;
- parsing, semantic analysis, templates, CTFE, type rules and most language
  lowering already exist;
- the current tree now also contains substantial AArch64 backend code;
- its object writers, symbol machinery, static-data representation, optimizer,
  register allocator and runtime-symbol machinery are preferable to bypassing
  them with target-specific mini-compilers.

Icky D lesson:

> A target should be restricted only where the target implementation is really
> missing. Do not create a second restricted definition of D.

The present experimental Thumb leaf emitter was useful to prove native
ARMv7/Thumb emission. It should remain a bootstrap/reference path, not become a
parallel implementation of arrays, structs, calls, globals, object generation
and the rest of ordinary D semantics.

Useful DMD areas to keep studying:

- `compiler/src/dmd/glue/`: frontend-to-backend lowering;
- `compiler/src/dmd/backend/`: common Mars machinery;
- `compiler/src/dmd/backend/arm/`: AArch64 implementation;
- `argtypes_*.d`: target ABI classification;
- `elfobj.d`, `dt.d`, `symbol.d`: object/data/relocation machinery;
- `drtlsym.d`: runtime helper symbols;
- DMD test suite: language and ABI regression corpus.

## LDC

Repository: <https://github.com/ldc-developers/ldc>

LDC uses the official DMD frontend and LLVM for code generation. It is the
strongest existing behavioral reference for D on targets Mars does not fully
support.

Android lessons accumulated by LDC are especially valuable:

- all four Android CPU ABIs have been supported;
- ARMv7 and AArch64 runtime libraries have existed in release packages;
- Android runtime initialization had to be made independent of a D `main()`;
- hidden visibility was used to reduce shared-library size;
- LLD support was added;
- historical Android TLS emulation required special compiler/linker work;
- newer Android support moved to native ELF TLS once the Android API floor
  permitted it;
- AArch64 C ABI and varargs work exposed subtle target-specific rules;
- frame-pointer policy matters for usable runtime backtraces.

Do not copy LLVM-specific machinery blindly into Mars. Instead use LDC for:

- expected ABI behavior;
- target triples and predefined versions;
- druntime configuration;
- runtime and standard-library test expectations;
- corner cases already found by years of ARM/Android use;
- differential compilation and execution.

Useful source/history:

- <https://github.com/ldc-developers/ldc/blob/master/CHANGELOG.md>
- <https://github.com/ldc-developers/ldc/issues/2153>
- <https://wiki.dlang.org/Build_D_for_Android>

## GDC and GCC

GDC uses the DMD-derived frontend with GCC's optimizer and target backends.

Primary references:

- <https://gcc.gnu.org/onlinedocs/gdc/D-Implementation.html>
- <https://gcc.gnu.org/git/gcc.git>

For **iCk**, GCC is the implementation foundation and GPL code is already in
the normal licensing world of that project. For **Icky D**, GDC/GCC remains an
exceptionally valuable implementation and behavioral reference; whether code
is copied directly depends on where that code will live and the chosen
licensing boundary.

What to mine:

- ARM EABI and AAPCS lowering;
- soft / softfp / hard-float distinctions;
- ELF relocation generation;
- PIC/GOT/PLT lowering;
- TLS models;
- atomic lowering;
- target builtins;
- unwind generation;
- GCC offload packaging and NVPTX/AMDGCN machinery;
- GDC's mapping from D frontend types and declarations into GCC IR.

Use GDC as a differential oracle against LDC and Icky D. If LDC and GDC agree
on an ARM ABI case while Icky D differs, investigate Icky D first.

## druntime and Phobos

Repositories:

- <https://github.com/dlang/dmd/tree/master/druntime>
- <https://github.com/dlang/phobos>

These are not an afterthought. A compiler that emits correct scalar arithmetic
but cannot satisfy the runtime ABI is not a complete Android D compiler.

Mine them for:

- target version branches;
- TLS and thread support;
- GC interfaces;
- exception/unwind assumptions;
- synchronization primitives;
- C ABI declarations;
- varargs implementation;
- floating-point environment;
- startup/shutdown;
- dynamic-library initialization;
- Android/Bionic special cases;
- tests that can be reused as target qualification.

A practical policy for Icky D should be:

1. qualify `-betterC` first;
2. then qualify the matching druntime boundary;
3. only then claim Phobos pieces whose tests pass.

---

# 2. D on Android projects

## adamdruppe/d_android

Repository: <https://github.com/adamdruppe/d_android>

Contains translated Android headers, NDK and Java bindings, setup helpers and
build instructions.

Useful lessons:

- D Android builds are ordinary native shared libraries from Android's point of
  view;
- build once per Android ABI and place the result in the corresponding
  `jniLibs/<abi>` directory when using an ordinary APK shell;
- use the Android NDK linker/toolchain, not the host linker;
- old LDC Android TLS behavior left visible integration scars, which are useful
  historical tests;
- Java bindings and NDK bindings are independent concerns.

Potential Icky D use:

- declarations and ABI-shape comparison;
- APK integration fixtures;
- simple interoperability corpus.

## Ryhon0/dondroid

Repository: <https://github.com/Ryhon0/dondroid>

A particularly useful specimen because it implements an Android
`NativeActivity` in D with no application Java source.

Architecture:

```text
APK NativeActivity
      |
android native glue in D
      |
android_main
      |
event / window / input loop
```

It uses LDC for D cross-compilation, the Android NDK toolchain for native
linking, and ordinary Android packaging/signing utilities.

This is strong prior art for an Icky-D-hosted GLES acceptance application:
there is no requirement that DEX be in the rendering path just to put D and
GLES on screen.

## DlangUI

Repository: <https://github.com/buggins/dlangui>

Cross-platform D UI with Android support and OpenGL acceleration.

Useful questions to mine rather than copying the framework wholesale:

- how Android context/window lifecycle is separated from rendering;
- how OpenGL function loading is handled;
- texture/font/image upload patterns;
- resource lifetime across context loss;
- event-loop integration;
- what Android-specific code was actually needed versus ordinary D code.

## BindBC-OpenGL

Repository: <https://github.com/BindBC/bindbc-opengl>

The important architectural fact is not merely that it provides OpenGL
bindings. Its loader and declarations were designed to support:

- `-betterC`;
- `@nogc`;
- `nothrow`;
- compile-time API/extension selection.

This is well aligned with early Icky D Android work. The host GLES/EGL layer
should not accidentally require full druntime merely because a binding library
did.

The older Derelict architecture is useful for comparison:

- <https://github.com/DerelictOrg/DerelictGLES>

BindBC's maintainers explicitly described BetterC/`@nogc`/`nothrow`
limitations in Derelict as reasons for the newer design. Treat that as a
concrete warning when designing Icky D's own low-level Android graphics
surface.

---

# 3. ARMv7 / Thumb-2

The ARM32 problem is not lack of community knowledge. It is transporting that
knowledge into the Mars backend cleanly.

## Normative Arm ABI material

Primary source:

- Arm ABI releases: <https://github.com/ARM-software/abi-aa>

The AAPCS32 documents should be the specification for:

- parameter/result classification;
- core versus VFP register use;
- stack alignment;
- homogeneous aggregates where relevant;
- callee/caller saved registers;
- variadics;
- interworking and function-pointer Thumb bits.

Android's `armeabi-v7a` ABI must then be checked against NDK documentation and
real linked objects.

## GCC ARM backend

GCC is a mature executable reference for:

- Thumb-2 instruction selection;
- soft, softfp and hard-float modes;
- prologues/epilogues;
- stack argument placement;
- PIC;
- TLS;
- atomics;
- branch veneers and relocations;
- builtins and helper calls.

The command-line ARM documentation is useful as a concise map of supported ABI
dimensions:

<https://gcc.gnu.org/onlinedocs/gcc/ARM-Options.html>

## LLVM ARM backend and compiler-rt

Repositories:

- <https://github.com/llvm/llvm-project/tree/main/llvm/lib/Target/ARM>
- <https://github.com/llvm/llvm-project/tree/main/compiler-rt>

LLVM's ARM backend is another independent implementation oracle. compiler-rt is
also important because apparently simple arithmetic operations can become
runtime helper calls.

LLVM's cross-compiling guide demonstrates a useful qualification shape:

- build ARM target code on a desktop host;
- run it under `qemu-arm` with a matching sysroot;
- keep target flags and ABI explicit;
- separate soft-float from hard-float test configurations.

QEMU is useful execution evidence, but not Android/Bionic/device evidence.

## binutils

Repository: <https://sourceware.org/git/binutils-gdb.git>

The ARM ELF relocation tables and object attributes are especially useful when
replacing the current relocation-free Thumb object path.

Important relocation families include:

- `R_ARM_THM_CALL`;
- `R_ARM_THM_JUMP24`;
- `R_ARM_THM_MOVW_*` / `MOVT_*`;
- GOT/PLT relocations;
- TLS relocations.

Also mine EABI attributes such as:

- CPU architecture/profile;
- Thumb ISA use;
- FP architecture;
- stack alignment;
- VFP argument convention.

## Idriç ARM/Thumb

This is a project-local source, but it belongs in this ledger because it is one
of the strongest references for the exact ARM32 work we care about.

Policy:

> When human-in-the-loop work settles an ABI rule, stack rule, instruction
> encoding, floating-point choice or acceptance fixture in Idriç ARM/Thumb,
> explicitly check whether Icky D can reuse the rule and test.

Do not fork the two compilers conceptually. They can have different IRs and
implementation languages while sharing:

- ABI fixtures;
- instruction encoding fixtures;
- device probes;
- stack/register invariants;
- numerical semantics;
- negative tests.

---

# 4. AArch64

AArch64 should require much less invention than ARM32 because Mars already has
a substantial backend.

Sources to compare continuously:

- DMD Mars AArch64 backend;
- LDC/LLVM AArch64;
- GDC/GCC AArch64;
- Android NDK Clang;
- Arm AAPCS64;
- physical Android objects and execution.

The current Icky D AArch64 Android leaf admission gate should be treated as a
qualification scaffold. It should not permanently reject a feature merely
because it was outside the first test slice.

For each rejected construct:

1. determine whether general Mars already emits it for AArch64;
2. identify the Android-specific ABI question, if any;
3. add a focused differential/ABI test;
4. remove the admission rejection only when that test is green.

This is preferable to reimplementing AArch64 operations in an Android-specific
emitter.

---

# 5. DEX and ART

DEX is a peer code-generation target, not a disguised ARM target.

The useful community work divides into file/bytecode writers, optimizing
compilers, verifier-aware IRs and direct-language backends.

## Android D8 / R8

Source:

- <https://r8.googlesource.com/r8/>
- <https://developer.android.com/tools/d8>

D8/R8 is the largest current body of production DEX compiler knowledge.

Architecture worth studying:

```text
input program
    |
high-level compiler IR
    |
optimization / desugaring
    |
register allocation
    |
DexBuilder
    |
DEX code + pools + debug + try/catch
```

`DexBuilder` demonstrates several things an Icky D backend will also need:

- virtual values must eventually receive DEX registers;
- instruction form depends on register number and literal width;
- branch sizes/offsets require staged construction;
- switch and fill-array payloads have placement/alignment constraints;
- try ranges and handlers are a separate encoded structure;
- debug events need their own finalization;
- methods record incoming, outgoing and total register counts.

D8 should not dictate Icky D semantics, but it is an excellent source for the
things ART will reject if encoded incorrectly.

## ReDex

Repository: <https://github.com/facebook/redex>

ReDex reads, transforms, type-checks and writes real production DEX.

Particularly useful areas:

- `IRTypeChecker`: verifier-compatible register type inference;
- register allocators;
- `InstructionLowering.cpp`;
- CFG representation;
- invoke-range conversion;
- packed versus sparse switch selection;
- Android-version-specific verifier/JIT workarounds.

Important lesson:

> DEX legality is not just an opcode table. Register type state, constructor
> rules, wide values, range invokes and historical ART/Dalvik quirks are part
> of the backend contract.

## smali / baksmali / dexlib2

Current Google-maintained fork:

- <https://github.com/google/smali>

This is useful at two layers.

First, smali is a readable canonical representation for tiny expected DEX
programs. It is ideal for early golden fixtures.

Second, dexlib2 supplies builders for:

- classes;
- fields;
- methods;
- instructions;
- labels;
- try/catch;
- annotations;
- debug information;
- complete DEX files.

An early Icky D experiment could use dexlib2 as a writer while Icky D owns
semantic lowering and register allocation. A later direct writer could remove
that dependency. Do not decide this before measuring how much the library
actually buys us.

## Soot / Jimple / Dexpler

Repository: <https://github.com/soot-oss/soot>

Jimple is a three-address IR used for Java/Android analysis. Soot can both read
DEX through Dexpler and emit DEX through its `toDex` layer.

This is strong architectural prior art for:

```text
language semantics
     |
typed three-address IR
     |
DEX-specific lowering
     |
dexlib2 writer
```

Useful details:

- local packing;
- branch and dead-code cleanup before emission;
- statement/expression visitors that produce DEX instructions;
- final correction of offsets, targets and register numbers;
- multidex writer.

## Skotch

Documentation: <https://skotch.dev/docs/architecture/>

This is one of the closest architectural matches found for the proposed Icky D
DEX target.

Skotch is a Kotlin compiler with a shared MIR and multiple backends:

```text
typed source
    |
three-address SSA-like MIR
    +---- JVM
    +---- DEX
    +---- LLVM
    +---- other targets
```

Its DEX backend writes DEX directly rather than invoking D8/dx. The documented
writer uses two passes:

1. collect and sort strings/types/fields/methods and other indexed objects;
2. write code using the resolved pool indices.

The direct lesson for Icky D is not “copy Kotlin's runtime model.” It is that a
shared typed middle representation can feed native and DEX backends without
making DEX concepts part of the source frontend.

## droidsaw-dex

Project: <https://github.com/droidsaw/droidsaw-dex>

A newer Rust DEX parser/decompiler/round-trip writer. It is not an Android
platform authority, but its engineering ideas are useful:

- DEX -> CFG -> SSA;
- explicit DEX type lattice;
- structured-region recovery;
- format-specific code isolated from generic CFG/SSA algorithms;
- round-trip/property testing;
- multidex references represented by stable descriptors rather than local pool
  indices.

Use these as test-design ideas; independently validate any claimed format
behavior against Android/R8/smali.

## ART itself

Source: <https://android.googlesource.com/platform/art/>

Eventually the most important DEX acceptance oracle is ART:

- verifier;
- interpreter;
- JIT;
- dex2oat/AOT;
- JNI/native bridge.

A generated `classes.dex` that parses in a third-party library but fails ART
verification is not accepted.

---

# 6. EGL / GLES host rendering

This path may be the shortest route from Icky D to useful GPU execution.

The compiler does **not** need to emit PowerVR or Mali machine code in order to
run a D-authored renderer.

```text
Icky D host code
      |
ARM ELF shared library
      |
EGL / GLES calls
      |
GLSL ES generated or embedded by the application
      |
vendor shader compiler
      |
physical GPU
```

For Pauli and similar applications, this means GLES is primarily a stress test
of ordinary native-D capabilities:

- external C calls;
- callbacks/function pointers;
- globals/static data;
- strings;
- arrays and slices;
- byte memory;
- PIC/relocations;
- shared-library output;
- Android lifecycle;
- math-library calls.

This is why the GPU path can become useful before a direct GPU machine-code
backend exists.

Community sources:

- Khronos OpenGL ES registry: <https://registry.khronos.org/OpenGL/>
- Khronos `gl.xml`: <https://github.com/KhronosGroup/OpenGL-Registry>
- DlangUI;
- BindBC OpenGL;
- DerelictGLES;
- dondroid/native-activity code;
- Android NDK native activity and EGL examples.

---

# 7. D compiled for GPUs

## DCompute + LDC

Repository: <https://github.com/libmir/dcompute>

DCompute is the strongest existing implementation of D itself as a device
language.

It separates:

- device-safe D semantics;
- device standard library/intrinsics;
- kernel entry points;
- address spaces;
- host runtime/dispatch;
- target code generation.

Established target paths include CUDA/PTX and OpenCL/SPIR-V. Current LDC work
also explores Vulkan compute, and Metal work has been proposed/developed.

What Icky D should learn:

- keep kernel/device intent explicit;
- address spaces are types/semantic metadata, not accidental pointers;
- validate unavailable runtime features before code generation;
- compile host and device images as separate target products;
- allow one source module to contain reusable host/device logic where semantics
  permit;
- keep packaging of device images distinct from the language frontend.

Do not copy DCompute's LLVM-specific implementation into Mars. The semantic
contract and tests are more portable than the code generator.

Relevant current work:

- LDC Vulkan DCompute PR #4958:
  <https://github.com/ldc-developers/ldc/pull/4958>
- DCompute Vulkan project:
  <https://dlang.github.io/GSoC/gsoc-2026/dcompute-vulkan.html>
- DCompute Metal project:
  <https://dlang.github.io/GSoC/gsoc-2026/dcompute-metal.html>

---

# 8. The actual physical GPU targets

The current target set is not abstract “GPU support”.

## PowerVR Rogue GE8322-class phone

Local primary research:

- <https://github.com/fuego-ironworks/idris-shader-backend>

The historical `target/powervr-ge8322-gles` branch contains a particularly
useful target survey. It must be mined, not merged wholesale.

The near-term executable boundary is:

```text
typed shader semantics
    |
GLSL ES 3.00
    |
Android GLES driver
    |
PowerVR compiler / USC
    |
PowerVR hardware
```

Public Imagination material documents enough to guide expression selection:

- FP16 SOP/MAD paths;
- FP32 MAD;
- reciprocal and reciprocal-square-root;
- exponential/log paths;
- packing/modifiers;
- tile-based rendering behavior.

It does **not** justify pretending we have a complete GE8322 native ISA
specification.

Primary references:

- <https://docs.imgtec.com/performance-guides/low-level-glsl/html/index.html>
- <https://docs.imgtec.com/starter-guides/powervr-architecture/html/index.html>
- <https://docs.imgtec.com/reference-manuals/powervr-instruction-set-reference/html/topics/general-architecture-information.html>

## Mesa PowerVR / PCO

Mesa documentation:

- <https://docs.mesa3d.org/drivers/powervr.html>

Mesa now contains an open PowerVR compiler stack under
`src/imagination/pco/`. Even if the exact phone/driver combination is not a
supported Mesa target, this is exceptionally valuable compiler prior art for
Rogue.

Observed architecture:

```text
SPIR-V / API input
      |
NIR
      |
PowerVR-specific lowering
      |
PCO SSA/hardware IR
      |
optimization
      |
graph-coloring register allocation
      |
instruction grouping
      |
legalization
      |
binary encoding
      |
USC
```

Important files to study:

- `pco_nir.c`;
- `pco_trans_nir.c`;
- `pco_ir.c`;
- `pco_opt.c`;
- `pco_ra.c`;
- `pco_group_instrs.c`;
- `pco_legalize.c`;
- `pco_binary.c`;
- `pco_isa.py`;
- `pco_map.py`;
- Vulkan-side `pvr_usc.c`.

A particularly important distinction is PowerVR's PDS versus USC work: shader
execution and task/data setup are separate concerns. Icky D should not flatten
resource setup, shader mathematics and machine execution into one IR.

## Mali-G57 MC1 / Valhall tablet

The Idriç shader target notes contain a physical-device Vulkan capability dump
from the tablet. Compiler-visible facts include:

- fixed subgroup width 16;
- Float16 shader arithmetic;
- 16-bit buffer/push/input-output storage;
- Int8 and Int16 shader support;
- no shader Float64;
- 32 KiB compute shared memory;
- 512 maximum compute workgroup invocations;
- F16/F32 signed-zero/Inf/NaN preservation capability;
- F16/F32 RTE and RTZ modes;
- accelerated signed and unsigned 8-bit dot products, including packed 4x8
  forms.

Treat those as driver-reported facts, not general facts inferred from the name
“Mali-G57”.

## Panfrost / PanVK

Mesa's Panfrost/PanVK stack is highly relevant because it supports Valhall and
Mali-G57-class hardware.

Sources:

- <https://gitlab.freedesktop.org/mesa/mesa/-/tree/main/src/panfrost>
- <https://www.collabora.com/news-and-blog/news-and-events/conformant-open-source-support-for-mali-g57.html>

A key historical result is that the Valhall compiler reused some Bifrost
compiler passes, including instruction-selection/register-allocation ideas, but
needed different scheduling for the changed ISA.

PanVK's compilation structure is a useful model:

1. SPIR-V/API input -> NIR;
2. common target-independent lowering/optimization;
3. API-specific descriptor and system-value lowering;
4. explicit address-space/I/O lowering;
5. target preprocessing;
6. Valhall machine compilation.

This separation is exactly what Icky D should preserve: D semantics, shader
semantics, Vulkan/GLES API semantics and GPU machine semantics are different
layers.

## Arm Mali Offline Compiler

Arm's offline compiler is a valuable optimization oracle.

It can report:

- work-register count;
- occupancy implications;
- stack spills;
- 16-bit arithmetic use;
- arithmetic/load-store/texture cycle estimates;
- more detailed FMA/CVT/SFU costs.

The Idriç notes correctly treat these numbers as target-compiler estimates, not
our own invented cycle model.

For Valhall generations including Mali-G57, the important practical register
boundary in Arm's guidance is approximately:

- 0-32 work registers: maximum occupancy;
- 33-64: reduced occupancy.

This should become a regression signal for representative shaders, not a
hard-coded register allocator in the Icky D frontend.

---

# 9. Shader IR lessons already learned in Idriç

These are worth carrying into Icky D before writing another shader backend.

## Preserve structured control flow

A source branch should remain a branch until the target can choose whether to
implement it with real control flow, predication or a select.

The Idriç `RSelect` experience is concrete evidence: flattening a branch caused
expensive work such as `atan`, `log`, `sqrt` and `pow` to execute eagerly,
then a later pass had to reconstruct branch structure.

Preferred IR concepts:

- typed binding;
- typed conditional with branch-local blocks;
- typed bounded loop;
- explicit loop-carried state.

Unrolling is a target optimization, not the semantic representation.

## Preserve reductions

A sum-of-squares or dot product is not merely an unordered bag of additions.
Keep the reduction object visible long enough to choose:

- reduction tree;
- accumulation width;
- subgroup implementation;
- shared-memory implementation;
- scalar fallback.

## Preserve precision intent

Idriç's current policy is a strong starting point:

- F16 and F32 are distinct semantic widths;
- no implicit F32 -> F16;
- portable GLES `mediump` is not automatically IEEE binary16;
- target capability evidence can justify stronger statements;
- choose width from actual numerical/output error budgets, not “more bits is
  better”;
- allow mixed precision by semantic stage.

## Preserve meaningful mathematical operators

Late target selection benefits from retaining operations such as:

- reciprocal;
- inverse square root;
- FMA intent;
- clamp/saturate;
- dot/reduction;
- normalization;
- two-coordinate rotation where it is truly a semantic operation;
- exact dyadic/triadic scale intent where relevant.

Do not prematurely scalarize an operation merely because GLSL can express its
scalar expansion.

## Separate evidence levels

Carry over the Idriç acceptance ladder:

1. semantic/reference oracle;
2. backend IR;
3. generated shader;
4. independent syntax/validation;
5. real driver compile/link;
6. renderer actually selects generated shader;
7. framebuffer/readback correctness;
8. physical GPU identity;
9. timing/performance characterization.

No higher level is implied by a lower one.

---

# 10. Other compiler architecture sources

These are secondary, but repeatedly useful.

## Mesa NIR

NIR demonstrates the value of a typed-ish common shader IR shared by multiple
APIs and many radically different GPUs.

Study:

- explicit control flow;
- SSA;
- algebraic optimization;
- deref/address-space lowering;
- API-independent versus API-specific passes;
- lowering only when the next layer requires it.

## SPIR-V tools and glslang

Repositories:

- <https://github.com/KhronosGroup/SPIRV-Tools>
- <https://github.com/KhronosGroup/glslang>

Useful for:

- SPIR-V validation;
- disassembly/inspection;
- canonical small shader fixtures;
- differential checks against a future Icky D SPIR-V emitter.

Validation success is not physical GPU acceptance.

## QEMU

Repository: <https://gitlab.com/qemu-project/qemu>

Useful for native ARM compiler tests and ABI probes. It does not prove:

- Bionic behavior;
- Android dynamic linker behavior;
- APK lifecycle;
- physical GPU behavior.

---

# 11. Proposed mining discipline

Before implementing a new Icky D target feature, search these sources in this
order.

## Native D / ARM feature

1. DMD general frontend/backend.
2. DMD AArch64 implementation.
3. LDC.
4. GDC/GCC.
5. druntime/Phobos tests.
6. Arm ABI specification.
7. Android NDK Clang/Bionic.
8. Idriç ARM/Thumb local evidence.

## DEX feature

1. Android DEX/ART specification/runtime behavior.
2. R8/D8.
3. ReDex.
4. smali/dexlib2.
5. Soot/toDex.
6. Skotch direct DEX backend.
7. independent round-trip tools such as droidsaw.

## GPU/shader feature

1. Idriç shader semantic/target notes and existing fixtures.
2. Khronos API/language specifications.
3. actual device capability receipt.
4. vendor documentation.
5. Mesa Panfrost/PanVK or PVR/PCO source.
6. Mali Offline Compiler or vendor-driver output.
7. DCompute/LDC where the problem concerns D-as-device-language design.
8. general GPU literature.

The point of this ordering is not authority for its own sake. It minimizes the
chance that Icky D invents a solution to a problem that the D community,
Android toolchain or actual target compiler has already solved and tested.
