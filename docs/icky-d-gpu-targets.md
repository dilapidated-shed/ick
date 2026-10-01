# Icky D GPU target notes: PowerVR GE8322 and Mali-G57

Status: research and planning only, 2026-09-30.

This document narrows Icky D GPU work to the two physical GPU families already
available to the project. It deliberately does not treat generic CUDA support
as the first milestone.

Primary local source mined:

- fuego-ironworks/idris-shader-backend
- main commit observed during this pass:
  4a29362e580df393e4d64a9929e4c1e592ac4c53
- historical target branches:
  target/powervr-ge8322-gles,
  target/mali-g57-mc1-valhall,
  opt/mali-g57-fp16-precision

The historical branches are research sources. Idriç's current AGENTS.md
explicitly says the PowerVR target branch is not the canonical integration base
and must not be merged wholesale.

---

# 1. Physical targets

## ARMv7 phone

Graphics identity to require at physical acceptance:

- vendor: PowerVR / Imagination;
- renderer: PowerVR Rogue GE8322-class device as reported by the driver.

Near-term API:

- EGL;
- OpenGL ES 3.x / GLSL ES.

Important distinction:

The compiler target we can own immediately is D or typed shader semantics to
GLSL ES plus the host EGL/GLES interaction. The Android vendor driver performs
the final GLSL-to-USC compilation.

~~~text
Icky D / shader semantics
          |
typed shader IR
          |
GLSL ES
          |
Android EGL/GLES
          |
PowerVR vendor compiler
          |
USC code
          |
PowerVR GPU
~~~

Direct USC machine-code emission is a separate possible target, not a
prerequisite for useful GPU work.

## AArch64 tablet

Physical graphics identity:

- GL_VENDOR: ARM;
- GL_RENDERER: Mali-G57.

Known Vulkan profile captured in Idriç shader:

- device: Mali-G57;
- proprietary Arm driver r51p0;
- Vulkan 1.3-class implementation;
- fixed subgroup width 16;
- Float16 supported;
- Int8, Int16 and Int64 supported;
- Float64 not supported;
- 16-bit storage supported for buffers, push constants and shader I/O;
- 8-bit storage supported;
- maximum compute workgroup invocations: 512;
- maximum compute shared memory: 32 KiB;
- F16/F32 signed-zero/Inf/NaN preservation capability reported;
- F16/F32 RTE and RTZ support reported;
- signed and unsigned 8-bit dot-product acceleration, including packed 4x8;
- VK_ARM_shader_core_builtins and VK_ARM_shader_core_properties exposed.

These are observations from that driver/device pair. They should become target
facts only behind a capability record, not hard-coded consequences of the
marketing name Mali-G57.

---

# 2. Why GPU may be an easier early path than the full Android renderer

There are two independent compiler products hiding under “GPU support”.

## Host renderer

Icky D must compile ordinary D into a native Android shared object which calls:

- EGL;
- GLES;
- Android input/window/event APIs;
- libc/libm;
- renderer helper functions.

This stresses ARM/Android code generation heavily.

## Shader compiler

A shader backend can be much smaller because the accepted execution model is
already constrained by the GPU language:

- no general heap;
- no arbitrary CPU pointers;
- no ordinary process calls;
- explicit shader interfaces;
- vectors and fixed arrays;
- structured control flow;
- well-known mathematical builtins.

The existing Idriç shader IR has already done substantial semantic design here.

Therefore the shader side may become productive before Icky D can compile the
whole Pauli NativeActivity. That does not mean weakening D globally. A shader
entry point is a deliberately different execution environment, just as a
CUDA/OpenCL kernel is.

---

# 3. Idriç shader architecture worth preserving

## Keep semantic IR above target spelling

The PowerVR branch states the rule clearly:

> The common shader IR is primary.

PowerVR or Mali target choices may change:

- precision qualifier;
- packing;
- expression form;
- resource representation;
- control-flow realization.

They should not redefine the mathematical program.

For Icky D, this argues for a shader-device boundary after ordinary D semantic
analysis, not a separate parser or “shader D” language.

Possible shape:

~~~text
DMD frontend
    |
ordinary D semantic AST / target-independent lowering
    |
identify shader / kernel entry region
    |
shader-safe typed IR
    |
+---------------------+
|                     |
GLSL ES             SPIR-V
|                     |
PowerVR GLES        Mali Vulkan
~~~

The exact annotation syntax is not chosen here.

## Structured conditionals

Idriç found a concrete failure from flattening a source case into eager branch
values followed by RSelect.

The result was expensive operations from both sides executing before the
selection.

The repair moved expensive closed dependency subgraphs back under GLSL if/else,
but the long-term note says the checked IR should represent the branch directly.

Icky D should start from the corrected architecture rather than reproduce the
failure.

Required semantic object:

~~~text
if condition
  then branch-local bindings -> value
  else branch-local bindings -> value
~~~

A later target may lower that to:

- real branch;
- predication;
- select;
- partial speculation.

The earlier IR should not force the answer.

## Bounded loops

The analytic-continuation work exposed the same issue for iteration. Manual
32+32 source expansion was necessary because the IR lacked a bounded loop.

Icky D shader IR should preserve:

- compile-time maximum bound where known;
- runtime active bound where needed;
- induction value;
- typed loop-carried state;
- body block;
- result.

Unrolling becomes a target optimization.

## Reductions

Keep dot products and sum-of-squares reductions visible. The target may select:

- scalar chain;
- vector operation;
- subgroup reduction;
- shared-memory tree;
- specialized instruction.

The reduction tree also affects floating-point error, so this is both a
performance and semantic issue.

---

# 4. Precision policy to import

Idriç has already done enough precision work that Icky D should not return to
“float means whatever GLSL does”.

## Semantic widths

Carry at least:

- F16;
- F32.

Rules:

- they are distinct;
- F32 -> F16 demotion is explicit;
- vector width and float width are independent;
- storage width and arithmetic width are independent;
- reductions and FMA/contraction need explicit numerical policy.

## GLES mediump

Portable GLSL ES gives minimum precision/range requirements. It does not let a
compiler claim that every mediump value is exact IEEE binary16.

For PowerVR, Imagination documentation gives stronger target information about
FP16 use. That justifies a target profile, not a global language rewrite.

## Error-budget rule

Idriç issue #61 states the useful rule:

> choose the coarsest representation whose arithmetic error is negligible
> relative to the output/error budget.

For graphical workloads, compare:

- fine mathematical oracle;
- algorithmic approximation;
- shader arithmetic/storage error;
- color transform error;
- framebuffer quantization;
- final visible/readback error.

If only one sensitive stage needs F32, do not automatically widen the entire
pipeline.

## Exact small-scale intent

Issue #62 adds another useful distinction: a semantic ratio such as 1/3 should
not become “the decimal digits we happened to print”.

For small dyadic/triadic scales, retain ratio identity as far as useful, then
make final floating encoding an explicit lowering step.

This fits Icky D's broader interest in compact/imprecise numerical types.

---

# 5. PowerVR-specific notes

Primary Idriç target notes:

- targets/powervr-ge8322/README.md;
- families/precision-and-usc.md;
- families/resources-and-pipeline.md;
- families/glsl-language.md;
- docs/powervr-hello-x.md.

## Public hardware/compiler facts worth remembering

The public Imagination material describes Rogue/Series8XE and the USC well
enough to guide GLSL expression choices, but not enough to claim a complete
GE8322 machine-code specification.

Useful documented operation families include:

- FP16 SOP/MAD;
- FP32 MAD;
- integer MAD/unpack;
- reciprocal;
- reciprocal square root;
- exponential/log operations;
- condition tests;
- pack/move/output paths;
- texture/interpolation.

Potential consequences to test, not assume:

- packed FP16 work may improve throughput;
- inversesqrt may expose a better normalization path;
- keeping MAD/FMA-shaped expressions may help;
- modifiers such as abs/negate/saturate may fold;
- exp2/log2 may map more directly to hardware paths;
- register pressure can dominate long polynomial/continuation shaders.

## Tile-based rendering

PowerVR is tile-based. Host scheduling/resource decisions can therefore matter
as much as arithmetic:

- avoid unnecessary external-memory traffic;
- use invalidate/discard appropriately;
- distinguish transient intermediate storage from persistent texture state;
- do not turn a sampler into a CPU-pointer abstraction;
- keep framebuffer/resource scheduling below shader mathematics.

## Physical acceptance

The Idriç PowerVR acceptance design should be copied conceptually.

Separate:

1. exact generated shader identity;
2. package identity;
3. target ABI;
4. EGL/GLES/GLSL identity;
5. vendor/renderer identity;
6. shader compile/link;
7. framebuffer readback;
8. timing.

Mesa/llvmpipe or SwiftShader is useful CI evidence, not PowerVR evidence.

---

# 6. Mesa PowerVR / PCO

Mesa's open PowerVR stack is an important source for Icky D research.

Driver docs:

https://docs.mesa3d.org/drivers/powervr.html

Compiler source:

src/imagination/pco/

The observed compiler decomposition is approximately:

~~~text
NIR
 |
PowerVR NIR preprocessing
 |
PCO IR
 |
optimization
 |
register allocation
 |
instruction grouping
 |
legalization
 |
binary encoding
~~~

Interesting implementation files:

- pco_nir.c
- pco_trans_nir.c
- pco_ir.c
- pco_opt.c
- pco_ra.c
- pco_group_instrs.c
- pco_legalize.c
- pco_binary.c
- pco_isa.py
- pco_map.py

The driver also separates USC shader execution from PDS setup/data/task
programming.

Lessons for Icky D:

- direct Rogue codegen is not conceptually impossible;
- it should be a late backend from a semantic shader IR, not embedded in the D
  frontend;
- register allocation and instruction grouping belong after generic
  optimization;
- resource setup and shader computation are separate layers;
- exact GE8322 support must be proved rather than inferred from “Rogue”.

Near-term recommendation: use this codebase as an oracle and architecture study,
while shipping through the phone's GLES compiler.

---

# 7. Mali-G57 / Valhall notes

## Valhall execution shape

Arm documentation describes:

- 16-wide warps/subgroups;
- native packed FP16/int16 and int8 paths;
- distinct arithmetic pipeline classes including FMA and special functions;
- load/store and texture pipelines;
- occupancy pressure from work-register count.

For the Mali-G57 family, keeping work registers at or below roughly 32 is an
important full-occupancy region according to Arm tooling/guidance.

That should not become a hard language rule. It is a measurement threshold for
generated code.

## Mali Offline Compiler

Use it as a compiler oracle.

Capture for representative shaders:

- work-register count;
- spill/no-spill;
- stack bytes/accesses where reported;
- 16-bit arithmetic fraction;
- arithmetic/load-store/texture cost;
- detailed FMA/CVT/SFU breakdown when useful.

Regression policy candidate:

- newly introduced stack spills are suspicious;
- crossing a register occupancy boundary is suspicious;
- lower GLSL source size is not automatically an improvement;
- actual tablet timing remains authoritative.

## Subgroups

The tablet reports fixed subgroup width 16.

For compute experiments:

- start with workgroup sizes that are multiples of 16;
- compare several sizes rather than assuming 512 is best;
- preserve reduction/collective semantics so subgroup lowering remains
  possible;
- do not make subgroup width 16 a source-language constant.

## 8-bit dot products

The tablet reports real acceleration for signed and unsigned 8-bit dot products
including packed 4x8.

This is interesting for genuinely quantized workloads. It is not a reason to
quantize floating geometry or orbital rendering merely to reach the unit.

---

# 8. Panfrost / PanVK

Panfrost is direct community evidence about Mali-G57-class compilation.

A particularly valuable historical lesson from bringing up Valhall is:

- Bifrost and Valhall were related enough to share compiler infrastructure;
- some passes such as register allocation could be reused;
- scheduling had to change for the new ISA.

This is exactly the kind of distinction Icky D should preserve between
semantic IR and generation-specific scheduling.

PanVK's flow gives a useful layering model:

~~~text
SPIR-V
  |
NIR
  |
common lowering/optimization
  |
Vulkan-specific descriptor/sysval lowering
  |
explicit memory/address-space lowering
  |
Panfrost preprocessing
  |
Valhall compiler
  |
machine code
~~~

Do not mix those layers in one D AST visitor.

Potential Icky D use:

- compare our generated SPIR-V with PanVK/NIR expectations;
- inspect what NIR transformations survive into the Valhall backend;
- learn which operations are kept native versus scalarized;
- inspect how FP16 and vector widths affect code;
- use Mesa as an independent compiler where the hardware/driver setup permits.

---

# 9. Near-term Icky D GPU paths

There are three increasingly ambitious paths.

## Path A: D host + generated GLSL ES

Lowest risk and directly useful on both devices.

~~~text
Icky D -> ARM .so
Idriç/Icky shader IR -> GLSL ES
ARM .so -> EGL/GLES -> vendor compiler -> GPU
~~~

First useful result:

- tiny NativeActivity or pbuffer program;
- backend-generated shader;
- physical renderer identity;
- framebuffer readback.

This path also pressures ordinary ARM D code generation.

## Path B: D -> shader-safe IR -> GLSL ES

This is the first actual Icky D GPU-language compiler.

Possible milestone:

~~~d
@fragment
float4 shade(float2 p) {
    // ordinary restricted D semantics
}
~~~

The exact syntax is not chosen.

The important requirement is that the ordinary DMD frontend performs parsing
and semantic analysis. The shader boundary then validates target-execution
constraints and lowers into the shared shader IR.

Do not build another D parser.

## Path C: D -> SPIR-V -> Vulkan on Mali

The tablet is a good first direct device-code target because:

- Vulkan capability data is already captured;
- Float16 and subgroup capabilities are known;
- Mesa PanVK provides an open independent compiler path;
- DCompute/LDC already demonstrates D -> SPIR-V as a language design.

This can be added after Path B has a stable shader semantic IR.

## Later: direct PowerVR or Valhall machine code

Research only until there is a compelling reason.

For PowerVR, Mesa PCO makes direct Rogue emission technically much more
approachable than it once was.

For Valhall, Panfrost contains a real open compiler.

But a direct hardware backend brings:

- ISA versioning;
- scheduling;
- register allocation;
- descriptor/task setup;
- driver/kernel interfaces;
- validation burden.

The vendor-driver GLSL/SPIR-V boundary is much cheaper and already reaches the
physical hardware.

---

# 10. Shared acceptance corpus to steal from Idriç

Icky D should reuse the questions and fixtures, even when implementations
differ.

Small mandatory probes:

- constant/pixel selection;
- block fill;
- dot4;
- larger dot/reduction;
- subtract + norm;
- Givens rotation;
- branch with expensive work on only one side;
- bounded loop;
- fixed array;
- F16 versus F32 numerical comparison.

Math workloads:

- Wegert phase/color;
- analytic continuation;
- polynomial/root workloads;
- rotations/normalization.

For every shader-producing target, preserve:

- source identity;
- typed IR dump;
- generated artifact;
- independent validation;
- target driver compile/link;
- output oracle;
- physical receipt when hardware claim is made.

---

# 11. Concrete research plan before implementation

No compiler changes are implied by this document.

## PowerVR

1. Copy the notes, not branch history, from Idriç's historical GE8322 target
   into the Icky D design record.
2. Read Mesa PCO around one simple float shader, one branch, one dot product,
   one texture operation.
3. Map the Idriç semantic operations to the PCO/NIR operations that preserve
   them.
4. Record what information would be lost by emitting naïve GLSL too early.
5. Keep GLES as the first executable path.

## Mali

1. Preserve the physical Vulkan capability profile.
2. Add Mali Offline Compiler output to the planned fixture receipts.
3. Study PanVK's common/API/target lowering boundaries.
4. Trace F16, branch, bounded loop, reduction and subgroup examples.
5. Plan SPIR-V only after the common shader IR is stable.

## Cross-target

1. Define a minimal shared typed shader IR.
2. Make F16/F32 explicit.
3. Make structured branches/loops explicit.
4. Keep reduction and selected numerical operations explicit.
5. Define interface/address-space metadata independently from CPU pointers.
6. Keep GLSL ES and SPIR-V as sibling emitters.
7. Require physical-hardware receipts only for claims about those GPUs.

The main architectural conclusion from mining Idriç and the community is that
the difficult part is not inventing GPU syntax. It is preserving enough
semantic structure that a late target backend or vendor compiler can still make
good choices.
