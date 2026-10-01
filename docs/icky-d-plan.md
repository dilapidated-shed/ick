# Icky D implementation plan after prior-art mining

Status: planning only, 2026-09-30.

This plan intentionally makes no compiler behavior changes. It turns the current
research into an order of work and evidence gates.

The major targets are peers:

- native ARMv7/Thumb-2;
- native AArch64;
- DEX/ART;
- shader/GPU outputs;
- later additional CPU/GPU targets.

No target should define a smaller version of D merely because its first
implementation is incomplete. A target-specific execution environment such as a
GPU shader may deliberately admit a subset, but that restriction belongs to the
execution environment, not to ordinary D.

---

# 0. Keep the names and project boundaries straight

Use these names in issues, branches and docs:

- Icky D: D compiler work.
- Icky C: C.
- IckY: yacc/parser.
- iCk: GCC-derived C compiler.

Current repository layout is historical and not authoritative naming. DMD work
currently lives on dmd-prefixed branches in the same repository that contains
iCk. Do not use “Ick” as a generic name for all four projects.

---

# 1. Stabilize the DMD base before expanding ARM

The current dmd-android-arm-backends branch diverged from dmd during the
research pass:

- 9 commits ahead of dmd;
- 19 commits behind dmd.

The overlap includes target-sensitive files such as:

- target.d;
- dmdparams.d;
- main.d;
- mars.d;
- cdef.d;
- elfobj.d;
- backconfig.d.

Before substantial ARM development:

1. reconcile the Android ARM branch with current dmd;
2. rerun all existing leaf/emulation tests;
3. preserve exact receipts;
4. make any conflicts explicit rather than silently choosing the old Android
   version of target machinery.

This is prerequisite housekeeping, not a feature milestone.

---

# 2. Replace “admission subset” with qualification for AArch64

AArch64 is the easiest native expansion because the general Mars AArch64
backend already contains substantial code for:

- calls;
- normal functions;
- ELF objects;
- relocations;
- data;
- register allocation;
- aggregate handling;
- optimization.

The Android branch currently inserts an armleaf validation layer before normal
AArch64 code generation.

Treat every current rejection as a question:

1. Does ordinary Mars AArch64 already generate this construct?
2. Is the generated ABI valid for Android/Bionic?
3. If not, what Android-specific difference is missing?
4. What minimal fixture proves the behavior?
5. Once proved, remove the rejection.

Do this feature family by feature family.

Suggested order:

1. internal calls;
2. external C calls;
3. globals and readonly data;
4. strings;
5. fixed arrays;
6. structs and aggregate layout;
7. more than four arguments;
8. function pointers/callbacks;
9. PIC/shared-library relocation cases;
10. byte/short memory;
11. integer/float conversions;
12. varargs;
13. TLS;
14. unwind/exceptions;
15. druntime/Phobos.

For each family compare:

- Icky D Mars output;
- LDC output;
- GDC output where convenient;
- NDK Clang for equivalent C ABI shapes;
- QEMU execution where useful;
- physical Android execution for the actual Android claim.

The goal is not “make the gate accept Pauli”. The goal is to make the gate
disappear wherever ordinary qualified DMD machinery is correct.

---

# 3. Turn ARMv7 Thumb from a leaf emitter into a real Mars target

The current Thumb proof path is useful but structurally limited:

~~~text
D semantic AST
    |
glue/thumb.d
    |
small custom Thumb emitter
    |
relocation-free, data-free ELF32 object
~~~

That was a good bootstrap because it proved:

- the DMD frontend can select an Android ARMv7 target;
- native Thumb instructions can be emitted;
- VFP Float32 can execute;
- scalar AAPCS softfp boundaries can be tested;
- DMD can write a valid enough ARM ELF object for the initial probes.

It should now become a reference implementation and test oracle.

The long-term target should look more like:

~~~text
DMD frontend
    |
ordinary DMD lowering / Mars IR
    |
shared optimizer / symbol / data machinery
    |
ARM32 target backend
    |
ELF32 + relocations
~~~

## 3.1 Add real ARM32 target identity to Mars

Avoid overloading the existing “arm means AArch64” boolean.

Introduce a target representation that can distinguish at least:

- x86;
- x86-64;
- ARM32;
- AArch64.

Then make backend initialization choose ARM32 explicitly.

## 3.2 Implement AAPCS32 argument classification

Today Target.toArgTypes returns null for Thumb because aggregate ABI
classification was intentionally postponed.

Add an ARM32 argument-classification module based on:

- AAPCS32;
- Android armeabi-v7a behavior;
- LDC/GDC comparison;
- Idriç ARM/Thumb fixtures.

Cover:

- integer/pointer words;
- 64-bit values;
- floats under the chosen softfp boundary;
- stack spill arguments;
- structs;
- return-in-memory cases;
- variadics separately.

Do not infer aggregate rules from the current four-scalar leaf convention.

## 3.3 Reuse common Mars IR and object machinery

Prefer teaching existing code about ARM32 over adding ARM32 versions of D
language constructs.

This is the most important architectural constraint.

Calls, static data, symbols, strings, structs, array representations,
relocations and runtime helper references already have generic representations.
The ARM32 backend should consume them.

## 3.4 ARM32 instruction selection

Mine three sources together:

- Idriç ARM/Thumb;
- GCC ARM;
- LLVM ARM.

Idriç is especially important whenever human review has already settled a rule
for the cheap-phone target.

Initial machine-code families:

1. moves/constants;
2. integer ALU;
3. loads/stores 8/16/32;
4. branches;
5. calls and returns;
6. stack frame/prologue/epilogue;
7. Float32 VFP;
8. integer/float conversions;
9. 64-bit integer pairs;
10. multiply/divide/helper calls as appropriate;
11. atomics later;
12. NEON later.

## 3.5 ELF and relocation support

Replace the current relocation-free object assumption.

First required families:

- local function references;
- R_ARM_THM_CALL;
- branch/jump relocations;
- absolute/relative data references;
- MOVW/MOVT relocations;
- GOT/PLT for PIC;
- Thumb function-symbol bit handling.

Then add TLS and unwind relocations only with matching runtime work.

## 3.6 Share qualification with Idriç

Every time Idriç gains a human-reviewed ARM result, ask whether the same fixture
belongs in Icky D.

Good shared fixtures:

- call with 0..N scalar args;
- stack alignment across nested calls;
- preserved registers;
- Float32 softfp boundary;
- load/store widths;
- pointer arithmetic;
- branches and long branches;
- function-pointer Thumb bit;
- relocations;
- PIC;
- negative ABI cases.

The implementations should remain independent enough to catch each other's
mistakes.

---

# 4. Android runtime is a separate workstream

Do not wait until code generation is “finished” and then discover that runtime
assumptions are wrong.

Use the LDC Android history as a checklist.

## BetterC gate

First Android claim:

- no druntime;
- no Phobos;
- external C interfaces only;
- shared object loads on Android;
- static data and callbacks work.

## Minimal runtime gate

Then qualify pieces needed by ordinary D:

- module initialization;
- TLS;
- thread attach/detach;
- allocation hooks;
- object/type information as required;
- exception/unwind support;
- GC only when actually introduced.

## Phobos gate

Do not claim “Phobos support” globally.

Run module/test families and record explicit support.

LDC's historical Android failures are useful test seeds:

- TLS;
- core.thread;
- core.sync;
- std.math;
- varargs;
- file/proc assumptions;
- dynamic-library initialization.

---

# 5. Make DEX a peer backend

Do not make DEX an afterthought behind JNI.

The high-level architecture should be:

~~~text
DMD frontend
     |
target-independent typed lowering
     |
shared middle representation
     |
+----------------------+---------------------+
|                      |                     |
Mars/native ARM        DEX                   shader/device
~~~

The shared representation need not be invented all at once. The first DEX
experiments can identify what minimum typed three-address representation is
actually needed.

## 5.1 First DEX milestone

Generate a valid classes.dex containing one class with one static method using:

- int constants;
- add/sub/mul;
- compare;
- branch;
- return.

Acceptance:

1. parse with two independent DEX tools;
2. disassemble with smali/baksmali;
3. verify/load under ART on Android;
4. invoke it from a tiny Android shell;
5. compare result against native D.

No Java source is required for the generated method itself.

## 5.2 DEX middle representation

Learn from Skotch, Soot/Jimple, R8 and ReDex.

Desired properties:

- typed three-address operations;
- basic blocks and explicit control flow;
- virtual locals before DEX register allocation;
- source-level type information retained long enough for verifier-safe lowering;
- explicit call prototype;
- explicit exception edges when exceptions arrive;
- no DEX pool index embedded before final writing.

## 5.3 DEX register allocation

DEX is register-based but instruction formats impose register-number and
contiguity constraints.

Study and test:

- narrow versus wide register forms;
- 64-bit values occupying register pairs;
- incoming parameter placement;
- invoke versus invoke/range;
- contiguous range arguments;
- move-result rules;
- constructor/uninitialized-reference verifier rules;
- register type joins across CFG edges.

ReDex IRTypeChecker should be treated as a catalogue of traps.

## 5.4 DEX file writer decision

Do not decide immediately between a direct writer and dexlib2.

Prototype both costs.

Option A:

~~~text
Icky D lowering
   |
Icky D register allocation
   |
dexlib2 builder
   |
classes.dex
~~~

Option B:

~~~text
Icky D lowering
   |
Icky D register allocation
   |
direct two-pass DEX writer
~~~

Skotch demonstrates that the direct writer is tractable:

1. collect/sort indexed strings, types, fields, protos and methods;
2. assign stable indices;
3. encode code/data with those indices;
4. compute checksums/signatures.

dexlib2 could make the first semantic experiments much faster.

## 5.5 Map D semantics deliberately

Do not pretend D is Java.

Research each feature:

- primitive ints/floats: mostly natural;
- D bool: define representation and verifier type;
- strings: decide Java String versus D-style immutable byte/char structure by
  execution context;
- static arrays: decide whether represented as DEX arrays, fields or flattened
  values;
- dynamic arrays/slices: likely explicit pair/object representation;
- structs: value flattening or synthetic classes depending context;
- pointers: no general managed DEX equivalent;
- function pointers/delegates: explicit synthetic callable representation;
- globals: static fields or runtime storage;
- TLS: runtime design;
- extern(C): native/JNI boundary, not a DEX calling convention;
- exceptions: map deliberately to ART exception machinery or reject until
  implemented;
- destructors/scope: explicit lowering, not JVM finalization semantics.

The correct mapping may differ between D code intended to stay purely in ART
and D code interoperating with native Icky D.

---

# 6. GLES renderer plan

This should be one of the earliest end-to-end applications because it exercises
real ordinary D without requiring a DEX backend.

## Stage 1: tiny BetterC host

Compile a D shared library containing:

- NativeActivity entry;
- EGL context setup;
- one GLES program;
- fullscreen triangle;
- framebuffer readback;
- log/receipt output.

C glue may remain temporarily for Android structs whose layout is best kept in
NDK headers.

## Stage 2: generated shader

Do not use a handwritten shader as the final compiler claim.

Feed an exact generated shader artifact from the Idriç/Icky shader backend.

Verify:

- source hash;
- driver compile;
- link;
- output;
- physical renderer identity.

## Stage 3: Pauli renderer

Use Pauli as a pressure fixture, not as the definition of backend support.

Pauli immediately demands:

- external EGL/GLES calls;
- callbacks;
- global/static state;
- readonly shader strings;
- byte arrays/pixels;
- structs;
- loops;
- math functions;
- fixed arrays;
- slices;
- PIC/shared-library relocation.

If Pauli fails, turn each failure into a general compiler feature fixture.

---

# 7. Icky D shader/GPU compiler plan

GPU execution is deliberately a separate environment from ordinary D.

The first implementation should reuse the ordinary DMD frontend and then lower
an explicitly selected shader/kernel region into a shared typed shader IR.

## 7.1 Do not invent a second D parser

The DMD frontend remains responsible for:

- syntax;
- name resolution;
- templates;
- compile-time evaluation;
- type checking.

The shader validator decides whether the resulting construct is valid in the
device environment.

## 7.2 Initial shader-safe feature set

Positive initial set:

- F16/F32;
- int/uint/bool;
- vectors/fixed arrays;
- local variables;
- arithmetic;
- comparisons;
- structured if/switch;
- bounded loops;
- pure helper functions;
- selected math builtins;
- typed shader inputs/outputs/uniforms.

Initial exclusions should be justified by the GPU environment:

- heap allocation;
- ordinary OS calls;
- host pointers;
- exceptions;
- recursion unless a target gives a clear model;
- arbitrary D runtime calls.

This is not the ARM “leaf subset” mistake because these restrictions describe
the execution environment itself.

## 7.3 Shared IR

Carry explicit nodes/metadata for:

- F16/F32;
- vectors;
- structured branches;
- bounded loops;
- reductions;
- reciprocal / inverse-square-root;
- FMA intent;
- clamp/saturate;
- texture/sample/derivative operations;
- shader stage;
- interface variables;
- address/resource space.

Adopt Idriç's lessons rather than re-discovering them.

## 7.4 First emitter: GLSL ES

Reason:

- reaches both physical GPUs now;
- vendor compiler handles machine scheduling/RA;
- easy to inspect;
- Idriç already has acceptance infrastructure;
- Khronos specifications are mature.

## 7.5 Second emitter: SPIR-V for Mali/Vulkan

Reason:

- physical tablet capability is already recorded;
- DCompute demonstrates D -> SPIR-V concepts;
- PanVK is an open independent target compiler;
- subgroup/F16 capabilities are useful for experiments.

Do not make SPIR-V the shared IR itself. It is a target representation.

## 7.6 Direct GPU machine code stays research

PowerVR Mesa PCO and Mali Panfrost make later direct backends conceivable.

Do not start there unless measurements show the vendor compiler boundary is a
real obstacle or direct emission itself becomes the research goal.

---

# 8. GPU optimization evidence plan

Never optimize from shader source aesthetics alone.

For PowerVR:

- physical framebuffer;
- timing;
- vendor renderer identity;
- generated GLSL;
- where possible driver/compiler diagnostics;
- Mesa PCO as an architectural comparison, not exact shipping-driver proof.

For Mali:

- physical framebuffer/timing;
- Mali Offline Compiler work-register count;
- spill status;
- F16 utilization;
- A/LS/T and detailed pipeline estimates;
- Panfrost/PanVK generated-code study where applicable.

Standing numerical rule:

- choose precision from actual error budgets;
- keep F16/F32 intent visible;
- promote only sensitive stages where possible;
- test hard cases around zeros, poles, cancellation and phase boundaries.

---

# 9. Testing ladder common to every target

## Compiler-local

- parse/type;
- IR shape;
- negative diagnostics;
- deterministic output.

## Differential

- DMD host where meaningful;
- LDC;
- GDC;
- NDK Clang for C ABI;
- D8/R8/smali for DEX structural comparisons;
- glslang/SPIR-V tools for shader validation.

## Emulated/software

- QEMU ARM;
- Mesa/llvmpipe;
- SwiftShader;
- local DEX parsers/interpreters.

These are useful but never silently promoted to physical target evidence.

## Physical

ARM:

- actual Android loader;
- Bionic;
- exact ABI;
- callbacks/runtime.

GPU:

- exact GL/Vulkan renderer;
- driver shader compile;
- execution;
- framebuffer/readback;
- timing.

DEX:

- ART verification;
- actual method invocation;
- JNI/native bridge where used.

---

# 10. Proposed branch sequence after the notes phase

No branch in this section should start until the notes are reviewed.

1. dmd-android-arm-reconcile
   - bring Android ARM work onto current dmd.

2. dmd-android-aarch64-general
   - feature-by-feature removal of artificial AArch64 leaf restrictions.

3. dmd-arm32-mars
   - real ARM32 backend integrated with normal Mars lowering/object machinery.

4. dmd-dex
   - first classes.dex backend experiments.

5. dmd-gles-host
   - BetterC Android EGL/GLES host fixture.

6. dmd-shader-ir
   - D frontend -> shared shader IR -> GLSL ES.

7. dmd-spirv
   - shader IR -> SPIR-V/Vulkan, beginning with Mali tablet.

This sequence does not imply serial completion. The workstreams can cross-check
each other, and a small DEX or shader prototype may proceed while ARM32 backend
work is still incomplete.

---

# 11. First acceptance milestones

Keep the first milestones very small and falsifiable.

## AArch64

A normal D module containing:

- global data;
- one internal call;
- one external C call;
- a small struct;

compiled by Icky D and executed on Android.

## ARMv7

Two ordinary non-leaf D functions where one calls the other plus an external C
function, with:

- relocation-bearing ELF;
- stack argument beyond four words;
- one byte load/store;
- one global.

Execute under QEMU and on the MIRO A1.

## DEX

One static arithmetic method emitted directly from D source and successfully
verified/invoked by ART.

## GLES host

One Icky D NativeActivity/pbuffer shared library that compiles and executes a
generated fragment shader and reads back known pixels.

## Shader compiler

One D-authored shader function lowered through the ordinary D frontend into the
shared shader IR and emitted as GLSL ES, with the same result on the PowerVR
phone and Mali tablet.

## SPIR-V

The same semantic shader emitted as SPIR-V and executed through Vulkan on the
Mali tablet.

---

# 12. Questions deliberately left open

These should not be answered by accident while implementing the first fixture.

- What exact shared middle IR should native and DEX backends share?
- Should DEX initially use dexlib2 or direct serialization?
- What D syntax/annotation selects a shader or kernel entry point?
- How much of Idriç shader IR should become a literal shared library versus a
  design/test source?
- Should shader compilation live inside Icky D immediately or first as a
  sibling experimental driver?
- When is direct PowerVR/Valhall code generation worth its cost?
- What Android API floor should full druntime target?
- How much runtime should DEX share with native D?
- Which precise mixed-precision annotations belong in source types versus IR
  analysis?

The rule for all of these is the same: collect evidence from the existing
community implementations and the actual devices before committing the
architecture.
