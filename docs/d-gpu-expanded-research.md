# D GPU expanded research ledger

Status: second research pass, 2026-09-27.

This file extends docs/d-gpu-prior-art.md with historical material, current
2025-2026 compiler work, direct LDC GPU targeting, concrete applications, and
negative/near-miss results. It is evidence collection, not an ICK architecture
decision.

## 1. The path from D host wrappers to native D kernels

### 2014: compiling D to SPIR was already being discussed

An LDC discussion in 2014 explicitly considered compiling a restricted D
program to SPIR for OpenCL:

- https://forum.dlang.org/thread/nnvoeygkdrckqgttzmdd@forum.dlang.org

The central difficulty identified there was address spaces. Ordinary D pointer
types did not express the distinctions required by GPU targets. This is useful
early evidence that D-to-GPU compilation is not merely a matter of selecting a
different LLVM triple.

### DConf 2016: CLWrap

John Colvin's DConf 2016 work used D templates and static introspection to
remove host-side OpenCL boilerplate:

- https://dconf.org/2016/talks/colvin.html

The kernels were still OpenCL kernels, so this is not itself native D device
compilation. It is nevertheless relevant prior art for deriving launch
signatures and argument handling from types instead of describing the same
interface twice.

### July 2016: early DCompute compiler prototype

The early DCompute announcement reported one LDC invocation producing:

- host code;
- CUDA PTX;
- OpenCL SPIR-V.

Sources:

- https://forum.dlang.org/thread/dhzcrzsnqjwvhuadjccm@forum.dlang.org
- https://www.digitalmars.com/d/archives/digitalmars/D/announce/dcompute_-_A_library_ldc_modifications_-_can_now_build_a_simple_add_44654.html

The implementation discussion is useful for ICK. The author described the
essential LDC changes as concentrated around:

- compiler-driver / main compilation flow;
- D-type to LLVM-type translation becoming aware of address spaces;
- device variants of code generation with host-only features such as classes
  and exceptions removed.

This is evidence that a D GPU compiler need not be a second parser or a
completely separate compiler. The important seam is semantic partitioning plus
target-aware type and ABI lowering.

### 2017: DCompute compiler support lands and kernels run

By 2017 the DCompute compiler changes were being integrated into LDC proper.

Sources:

- https://forum.dlang.org/thread/zcfqujlgnultnqfksbjh@forum.dlang.org?page=1
- https://dconf.org/2017/talks/wilson.html

A September 2017 report showed a SAXPY-style kernel written in D and actually
executed through the CUDA driver:

- https://forum.dlang.org/thread/smrnykcwpllukwtlfzxg@forum.dlang.org

The two D blog articles from the period are also implementation references:

- https://blog.dlang.org/2017/07/17/dcompute-gpgpu-with-native-d-for-opencl-and-cuda/
- https://blog.dlang.org/2017/10/30/d-compute-running-d-on-the-gpu/

They show two ideas that remain useful:

1. D reflection can derive kernel names/signatures and host argument packing.
2. A restricted GPU subset can retain templates, CTFE, value types and other
   useful D features even when GC, exceptions, RTTI and virtual dispatch are
   unavailable.

### FOSDEM 2018 retrospective

Kai Nacke's FOSDEM 2018 talk, Heterogeneous Computing with D, is a concise
compiler implementation record:

- https://archive.fosdem.org/2018/schedule/event/heterogenousd/
- https://archive.fosdem.org/2018/schedule/event/heterogenousd/attachments/paper/2417/export/events/attachments/heterogenousd/paper/2417/HeterogeneousComputingwithD.pdf

It identifies the concrete compiler requirements:

- address-space-aware pointer lowering;
- GPU-specific calling conventions;
- kernel metadata;
- multiple target compilations from one application source;
- separate DataLayout / Target / ABI state.

The talk also identifies mutable compiler-global target state as a practical
obstacle. ICK should not assume that a compiler process has only one active
machine world if a single invocation can emit host code and several device
images.

## 2. Direct LDC GPU targeting without DCompute

A major finding from the second pass is that LDC can target GPU LLVM backends
directly even without the full DCompute programming model.

### NVPTX and AMDGCN builtins

LDC PR #3411, merged in 2020, added generated D declarations for NVIDIA NVVM
and AMDGCN LLVM builtins:

- https://github.com/ldc-developers/ldc/pull/3411

A maintainer demonstrated direct NVPTX compilation with this D source:

~~~
import ldc.gccbuiltins_nvvm;

double foo(double a, double b)
{
    return __nvvm_add_rm_d(a, b);
}
~~~

and this compiler shape:

~~~
ldc2 -c bla.d -betterC -mtriple=nvptx64 -mcpu=sm_50
~~~

The distinction is important:

1. LDC can lower D expressions for a GPU target.
2. D can name low-level GPU intrinsics.
3. DCompute adds the higher-level kernel/offload semantics, address-space
   vocabulary, device library, packaging and launch runtime.

These are separate capabilities and should remain separate layers in ICK.

### Hundreds of NVVM operations are available

A 2021 LDC discussion reports that generated NVVM declarations gave D access
to hundreds of LLVM NVVM intrinsics. Synchronization and warp-shuffle examples
lowered to the expected PTX instructions.

Sources:

- https://forum.dlang.org/thread/mdgkvutlshkdkksylhvw@forum.dlang.org
- https://www.digitalmars.com/d/archives/digitalmars/D/ldc/ldc_nvvm_GPU_intrinsics_good_news_5158.html

The same LDC machinery also generated an AMDGCN builtin module.

LDC additionally has an LLVM-IR escape hatch through ldc.llvmasm.__irEx for
cases where a suitable high-level intrinsic declaration is absent.

This suggests a useful layering for ICK:

~~~
ordinary D
    |
device-safe D
    |
target-independent GPU operations
    |
target-specific intrinsic layer / explicit escape hatch
    |
NVPTX | AMDGCN | SPIR-V | AIR | ...
~~~

### AMDGCN exists as a backend but not a complete DCompute path

A 2022 discussion asked how to compile D directly for AMD GCN. The LDC target
exists, but DCompute did not then provide a complete AMDGCN kernel/runtime
path. Nicholas Wilson suggested SPIR-V plus OpenCL as the practical path for
AMD hardware.

- https://forum.dlang.org/thread/hjpjztchwtdybqbhmyrd@forum.dlang.org

So "the compiler backend can emit AMDGCN" and "D has a complete AMD GPU
programming model" are separate milestones.

## 3. DCompute's device standard library

DCompute is not only a host driver wrapper. Its device-side standard library
provides target-independent operations implemented with target-specific
intrinsics.

Representative modules:

- https://github.com/libmir/dcompute/blob/master/source/dcompute/std/index.d
- https://github.com/libmir/dcompute/blob/master/source/dcompute/std/sync.d
- https://github.com/libmir/dcompute/blob/master/source/dcompute/std/atomic.d
- https://github.com/libmir/dcompute/blob/master/source/dcompute/std/memory.d
- https://github.com/libmir/dcompute/blob/master/source/dcompute/std/floating.d
- https://github.com/libmir/dcompute/blob/master/source/dcompute/std/integer.d
- https://github.com/libmir/dcompute/blob/master/source/dcompute/std/warp.d

The pattern is:

~~~
D-facing device operation
    |
target reflection
    +-- CUDA / NVVM implementation
    +-- OpenCL / SPIR-V implementation
~~~

Indexing, barriers, atomics and memory operations are therefore not forced to
leak CUDA or OpenCL names into ordinary kernel source.

For ICK this is prior art for a small shared device vocabulary above individual
GPU machine backends.

## 4. DCompute and LDC are active in 2026

The deeper search changes the picture materially: this is not merely a 2017
experiment being kept alive mechanically.

Recent libmir/dcompute work includes:

- February 2026: expanded OpenCL math builtins;
- March 2026: LDC 1.42 support;
- May 2026: CUDA Unified Memory;
- May 2026: CUDA driver migration from Derelict to BindBC;
- June 2026: kernel image embedding and less-manual launch setup;
- July 2026: CUDA/OpenCL correctness and device-code fixes.

Repository:

- https://github.com/libmir/dcompute

Recent LDC compiler work includes:

- device array comparison/equality lowering;
- in-device memcmp replacement;
- disabling host exception-based bounds-check paths in device code;
- address-space preservation fixes;
- native embedded PTX/SPIR-V images;
- Vulkan pointer ABI preparation;
- hardware-verified ref-return address-space fixes.

### CUDA Unified Memory

DCompute PR #94, merged 2026-05-12, added UnifiedBuffer!T using CUDA managed
memory:

- https://github.com/libmir/dcompute/pull/94

The important compiler-design lesson is that explicit copies are not the only
memory model. The language should not bake "host buffer copied to device
buffer" into its fundamental GPU semantics.

Potential memory policies include:

- device-only allocation;
- explicit copy;
- unified/managed memory;
- coherent shared memory;
- target-specific local/shared memory.

### Embedded kernel images

DCompute PR #98, merged 2026-06-25:

- https://github.com/libmir/dcompute/pull/98

LDC PR #5140, merged 2026-06-16:

- https://github.com/ldc-developers/ldc/pull/5140

LDC now supports embedding generated PTX and SPIR-V into the host executable
while retaining the ability to emit sidecar device files.

The historical progression is instructive:

~~~
standalone PTX/SPIR-V
    |
library/build-system embedding
    |
compiler-native embedded device images
~~~

ICK should probably preserve both inspectable sidecars and deployable embedded
images rather than forcing one packaging choice.

## 5. Vulkan is active work, not merely a hypothetical target

Two LDC pull requests form the current Vulkan line:

- original draft #4958:
  https://github.com/ldc-developers/ldc/pull/4958
- current integration/rework #5132:
  https://github.com/ldc-developers/ldc/pull/5132

The work includes or experiments with:

- Vulkan DCompute target selection;
- a Vulkan target ID and target reflection;
- Vulkan-specific SPIR-V ABI behavior;
- a SPIR-V/Vulkan target triple;
- synthesized compute-kernel entry wrappers;
- workgroup-size metadata;
- SPIR-V optimization.

The whole Vulkan backend is still unmerged as of 2026-09-27, but preparatory
pieces have already landed.

### Kernel dimensions moved into the annotation

LDC PR #4945, merged 2025-06-08, changed the kernel annotation to a function
UDA and added optional dimensions:

~~~
@kernel([2, 4, 8])
void foo(...)
~~~

- https://github.com/ldc-developers/ldc/pull/4945

The PR specifically notes that Vulkan needs this information. That means launch
geometry can be compile-time kernel metadata, not only a host runtime launch
parameter.

### Pointer ABI groundwork merged in September 2026

LDC PR #5282, merged 2026-09-07:

- https://github.com/ldc-developers/ldc/pull/5282

It adds Vulkan as a recognized DCompute target and changes pointer ABI lowering
to support SPIR-V pointer typing/address-space requirements.

LDC PR #5285, merged 2026-09-09:

- https://github.com/ldc-developers/ldc/pull/5285

This fixes a real ref-return bug for GlobalPointer!T. CUDA can convert a global
pointer to its generic pointer space; the corresponding SPIR-V situation may
not admit that conversion and must be diagnosed.

That is strong evidence that address space is part of intermediate type and
reference semantics, not decorative metadata to bolt on at final emission.

## 6. Metal work has both compiler and runtime sides

Compiler work:

- LDC #5118:
  https://github.com/ldc-developers/ldc/pull/5118

Runtime/driver work:

- DCompute #99:
  https://github.com/libmir/dcompute/pull/99

As of 2026-09-27, DCompute #99 is open and was updated 2026-09-19. It contains
concrete Metal device, buffer, program and queue code rather than only a stub.

The current pipeline is approximately:

~~~
D kernel
   |
LDC
   |
LLVM IR plus Apple AIR metadata
   |
LLVM bitcode compatibility downgrade
   |
xcrun metallib
   |
.metallib
   |
Metal runtime loading and dispatch
~~~

The compatibility step exists because the LLVM bitcode emitted by the compiler
and the form accepted by Apple's toolchain need not match directly.

For ICK this is useful evidence that "GPU backend" cannot always mean "emit an
assembly/object file and stop". Some targets require a vendor-specific
post-processing and packaging step.

There is also an earlier Metal driver skeleton:

- https://github.com/libmir/dcompute/pull/91

The newer #99 is the more useful runtime implementation reference.

## 7. DirectX / DXIL was also tried

LDC PR #5181 was an unmerged DirectX DCompute target scaffold:

- https://github.com/ldc-developers/ldc/pull/5181

It experimented with:

- directx target selection;
- a DXIL target triple;
- HLSL-style compute-shader attributes;
- thread-group metadata.

The PR was closed without merging. This is not a current LDC capability.

It is still useful evidence that the DCompute source abstraction can be tested
against device object models beyond CUDA and OpenCL.

## 8. Recent compiler bugs reveal the real hard parts

Recent LDC fixes are a useful failure-mode catalogue.

The issues have included:

- conditional expressions dropping device pointer address spaces;
- ref returns accidentally dereferencing an address instead of returning it;
- host-only comparison/equality runtime hooks needed by otherwise valid device
  D expressions;
- memcmp needing an inline device implementation because there is no host libc;
- ordinary D bounds-check failure lowering being unusable because it throws;
- device ABI / target state leaking back into host code generation.

Relevant sources:

- https://github.com/ldc-developers/ldc/pull/5140
- https://github.com/ldc-developers/ldc/pull/5282
- https://github.com/ldc-developers/ldc/pull/5285
- https://github.com/ldc-developers/ldc/commit/76d0e765b3b7f4a073f526205213c1953c310007
- https://github.com/ldc-developers/ldc/commit/08a3b29b0c9a48b7df862c9f38cbf0b2d1663a61

This is evidence against implementing GPU support as only a late backend.
Semantic lowering and runtime-hook selection need device awareness too.

## 9. OpenCL/SPIR-V maintenance history

Historically, DCompute needed a custom SPIR-V LLVM target, which made the
OpenCL path materially harder to build and maintain:

- https://www.digitalmars.com/d/archives/digitalmars/D/ldc/How_to_build_SPIR-V_supported_LDC_4071.html

Modern LLVM has a SPIR-V backend, but interface churn still matters. LDC issue
#4998 tracked a crash on newer LLVM versions caused by an OpenCL barrier
declaration/backend lowering mismatch:

- https://github.com/ldc-developers/ldc/issues/4998

The reduced example helped separate an LDC/DCompute surface issue from an LLVM
SPIR-V backend issue.

ICK should therefore have acceptance tests at more than one boundary:

- source semantics accepted;
- compiler IR structurally correct;
- generated device IR accepted by downstream assembler/driver;
- physical execution correct.

## 10. Concrete nontrivial DCompute example

This repository ports NVIDIA's stereo-disparity CUDA sample to D using the
DCompute CUDA backend:

- https://github.com/aferust/stereoDisparity-dcompute-dcv

That is useful beyond SAXPY because it exercises more realistic indexing,
buffers and image-like data.

A sensible ICK sequence is still to start with a tiny kernel receipt, but the
second acceptance program should be complex enough to expose address-space and
launch-shape errors.

## 11. Near-misses: useful host prior art, not D-to-GPU compilers

### cuda_d

- https://github.com/prasunanand/cuda_d

This is D binding work for CUDA/cuBLAS/cuRAND and related APIs. It does not
compile D kernel bodies to the GPU.

### d-nv

- https://github.com/ShigekiKarita/d-nv

This wraps NVRTC from D and provides typed host-side kernel handling. The
device kernel remains CUDA source passed to NVRTC.

### dlang-cuda-ex

- https://github.com/phaistos/dlang-cuda-ex

This is CUDA API experimentation from D, again not native D device
compilation.

These projects may still contain useful ideas for typed argument packing,
device discovery and launch APIs. They should remain categorized separately so
host FFI convenience is not mistaken for compiler support.

## 12. GCC/GDC result from the deeper search

The GCC tree used by GDC contains mature GPU/offload infrastructure:

- gcc/omp-offload.cc;
- NVPTX target support;
- AMD GCN target support;
- target-specific mkoffload machinery;
- libgomp plugins and device runtimes;
- offload tests and target metadata.

Useful source entry points:

- https://github.com/D-Programming-GDC/gcc/blob/master/gcc/omp-offload.cc
- https://github.com/D-Programming-GDC/gcc/blob/master/gcc/config/gcn/mkoffload.cc
- https://github.com/D-Programming-GDC/gcc/blob/master/libgomp/plugin/plugin-nvptx.c

A focused search of gcc/d in the GDC GCC tree did not find a D-specific
OpenMP/OpenACC/offload front-end implementation.

That is a negative search result, not a proof that no experiment has ever
existed. For ICK planning, the evidence currently supports this split:

- GCC already has much of the device compilation and packaging machinery.
- A D-facing semantic entry point still appears to need work.

This makes the GDC-derived route interesting precisely because the expensive
machine/runtime half is already nearby.

## 13. Revised architecture map for ICK

The prior art now breaks into six separable layers.

### 1. D semantic partition

Responsibilities:

- device-only vs host-and-device code;
- kernel entry points;
- validation/replacement of host-only language/runtime behavior.

### 2. Device type and memory semantics

Responsibilities:

- global/shared/constant/private/generic memory;
- pointer and reference behavior;
- preservation through calls, aggregates and conditionals;
- memory policy independent of one runtime.

### 3. Target-independent device library

Responsibilities:

- thread/workgroup indices;
- barriers;
- atomics;
- memory operations;
- math;
- packing/conversion operations.

### 4. Machine/device lowering

Potential targets:

- NVPTX;
- AMDGCN;
- SPIR-V;
- AIR/Metal;
- later DXIL or another target.

### 5. Device image production and packaging

Responsibilities:

- inspectable sidecar artifacts;
- embedded images;
- target-specific post-processing;
- device linking and possibly device LTO.

### 6. Host runtime and launch

Responsibilities:

- device discovery;
- buffers and memory policies;
- queues/streams;
- argument packing;
- kernel lookup;
- launch.

DCompute demonstrates all six layers to some degree. GCC already implements
large pieces of the lower layers for its own offload model. ICK should keep the
layers explicit so it can reuse GCC machinery without copying LDC's
LLVM-specific implementation.

## 14. Bounded implementation experiments suggested by the evidence

The research now suggests this order for implementation receipts.

### Receipt 1: direct device emission

Compile one tiny D function through the GCC-derived ICK path to an inspectable
GPU artifact, initially NVPTX or AMDGCN. No launch runtime is needed yet.

### Receipt 2: address-space preservation

Carry one explicit global-memory pointer through a load/store and inspect the
target IR/assembly to prove the intended memory space survived lowering.

### Receipt 3: kernel entry

Mark one D function as a kernel using an ICK/D semantic mechanism rather than
importing C/C++ OpenMP syntax. Verify the required target calling convention
and metadata.

### Receipt 4: host/device split

Compile one source unit into ordinary host code plus one device image.

### Receipt 5: image embedding

Embed the device image into the host artifact while preserving a switch that
emits the same image separately for debugging and inspection.

### Receipt 6: physical launch

Run a minimal kernel on hardware after all of the compiler-side artifacts are
independently inspectable.

This keeps the first implementation small while avoiding a CUDA-only design.

## 15. Source ledger

Historical D work:

- https://forum.dlang.org/thread/nnvoeygkdrckqgttzmdd@forum.dlang.org
- https://dconf.org/2016/talks/colvin.html
- https://forum.dlang.org/thread/dhzcrzsnqjwvhuadjccm@forum.dlang.org
- https://dconf.org/2017/talks/wilson.html
- https://blog.dlang.org/2017/07/17/dcompute-gpgpu-with-native-d-for-opencl-and-cuda/
- https://forum.dlang.org/thread/smrnykcwpllukwtlfzxg@forum.dlang.org
- https://blog.dlang.org/2017/10/30/d-compute-running-d-on-the-gpu/
- https://archive.fosdem.org/2018/schedule/event/heterogenousd/

Current LDC and DCompute:

- https://github.com/ldc-developers/ldc/pull/3411
- https://github.com/ldc-developers/ldc/pull/4945
- https://github.com/ldc-developers/ldc/pull/5118
- https://github.com/ldc-developers/ldc/pull/5132
- https://github.com/ldc-developers/ldc/pull/5140
- https://github.com/ldc-developers/ldc/pull/5175
- https://github.com/ldc-developers/ldc/pull/5181
- https://github.com/ldc-developers/ldc/pull/5282
- https://github.com/ldc-developers/ldc/pull/5285
- https://github.com/libmir/dcompute/pull/94
- https://github.com/libmir/dcompute/pull/98
- https://github.com/libmir/dcompute/pull/99
- https://github.com/ldc-developers/ldc/issues/4998

Concrete/nearby projects:

- https://github.com/aferust/stereoDisparity-dcompute-dcv
- https://github.com/prasunanand/cuda_d
- https://github.com/ShigekiKarita/d-nv
- https://github.com/phaistos/dlang-cuda-ex
