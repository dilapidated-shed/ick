# D → GPU prior art

Status: initial research pass, 2026-09-27.

This note collects prior art for compiling D source into GPU device code and
identifies compiler seams that may be useful to ICK. It is deliberately a
research note, not yet a design decision.

## Short answer

There is real prior art for compiling D itself to GPU code.

The strongest implementation is **DCompute + LDC**. DCompute marks D modules
and functions as device code; LDC performs a GPU-specific semantic check,
lowers the accepted D subset into a separate LLVM module for each requested
compute target, and emits CUDA/NVPTX or OpenCL/SPIR-V device code. Current LDC
can generate host code and more than one device target in one compiler
invocation.

For ICK specifically, the other important prior art is **GCC's existing
offload machinery**. GCC already knows how to package and compile device code
for targets including `nvptx-none` and `amdgcn-amdhsa`. That machinery is
currently exposed through OpenMP/OpenACC in C, C++, and Fortran; the GDC
documentation does not show an equivalent D-language offload syntax. It is
still relevant because ICK is GCC-derived and the offload target/middle-end
machinery already exists independently of a D surface syntax.

The architectural question for ICK is therefore not "can D reach a GPU?" but
which pieces of existing machinery should be reused and where the
host/device boundary belongs in ICK's language and IR.

## 1. DCompute and LDC

Primary project:

- https://github.com/libmir/dcompute
- https://github.com/ldc-developers/ldc

DCompute describes itself as a set of libraries used with LDC for native
execution of D on GPUs and other accelerators. Its documented production
targets are CUDA and OpenCL.

### Source-level model

LDC provides compiler-recognized D declarations in:

- https://github.com/ldc-developers/ldc/blob/master/runtime/druntime/src/ldc/dcompute.d

Important pieces:

- `@compute(CompileFor.deviceOnly)` marks a module for device compilation.
- `@compute(CompileFor.hostAndDevice)` permits the same module to be emitted
  for host and device.
- `@kernel()` marks a GPU entry point, analogous to CUDA `__global__` or an
  OpenCL kernel.
- `Pointer!(AddrSpace, T)` and aliases such as `GlobalPointer!T`,
  `SharedPointer!T`, and `ConstantPointer!T` make device address spaces
  explicit in the D type system.
- `__dcompute_reflect` supplies code-generation-time target reflection so one
  D module can select backend-specific intrinsics or behavior.

The address-space abstraction is especially relevant to ICK: DCompute defines
one target-independent vocabulary and maps it to the target backend's address
spaces. CUDA/NVPTX and SPIR-V do not have to leak into ordinary D source.

### Device-language subset

LDC has a dedicated semantic validator:

- https://github.com/ldc-developers/ldc/blob/master/gen/semantic-dcompute.cpp

The validator intentionally rejects D features that require unavailable host
runtime behavior or are difficult to give portable device semantics. Current
examples include:

- classes and interfaces;
- associative arrays;
- global variables in ordinary device modules;
- `new` and `delete`;
- dynamic array concatenation and resizing;
- exceptions and `catch`;
- `synchronized`;
- function pointers and delegates;
- `typeid`;
- inline assembly;
- string literals;
- calls into non-`@compute` modules, except for narrowly admitted compiler
  lowering hooks.

The file also states the positive contract: device functions are intended to
be `@nogc`, `nothrow`, and closed over other compute-safe functions.

This is useful prior art even if ICK chooses a different accepted subset. A
GPU target needs an explicit semantic contract rather than simply hoping that
arbitrary host D lowers.

### Code-generation seam

LDC's code-generation manager is documented directly in:

- https://github.com/ldc-developers/ldc/blob/master/driver/dcomputecodegenerator.h

Its key invariant is:

> all `@compute` D modules are emitted into one LLVM module once per target.

That is a clean seam. Front-end D semantics are processed once; then each
device target receives its own module and target ABI/address-space lowering.

The multi-target test is:

- https://github.com/ldc-developers/ldc/blob/master/tests/codegen/dcompute_dual_targets.d

It verifies one compiler invocation generating:

- host code;
- CUDA device code;
- OpenCL device code.

The current command-line mechanism is `-mdcompute-targets`, with forms such
as `cuda-800` and `ocl-300`.

### Outputs

For the established backends:

- CUDA is lowered through LLVM NVPTX and produces PTX.
- OpenCL is lowered through LLVM's SPIR-V path and produces SPIR-V.

DCompute's build documentation:

- https://github.com/libmir/dcompute#build-instructions

LDC's target selection/code-generation sources:

- https://github.com/ldc-developers/ldc/blob/master/driver/dcomputecodegenerator.cpp
- https://github.com/ldc-developers/ldc/blob/master/driver/targetmachine.cpp

The fact that LDC uses SPIR-V here should not by itself be read as "Vulkan is
already supported". The established DCompute runtime/documentation is for the
OpenCL environment.

### Current state in LDC 1.43

LDC 1.43.0 was released on 2026-08-30. Its changelog records native embedding
of DCompute device code (PTX and SPIR-V) into the host executable's
`.rodata` section.

- https://github.com/ldc-developers/ldc/blob/master/CHANGELOG.md

The DCompute CUDA tests now exercise loading PTX from the compiled module and
launching it without requiring a separately managed PTX file:

- https://github.com/libmir/dcompute/blob/master/source/dcompute/tests/main.d

This is important prior art for ICK packaging: a host executable can carry
its device images as ordinary compiler-produced data rather than forcing the
application to manage sidecar blobs.

## 2. Metal work in progress

As of 2026-09-27, Metal support is not part of the established LDC/DCompute
baseline. There is an open LDC pull request:

- ldc-developers/ldc#5118, "Initial Metal backend support to dcompute"
- https://github.com/ldc-developers/ldc/pull/5118

The proposed implementation extends DCompute with a Metal/AIR target, adds
Metal-specific address-space and kernel metadata lowering, and uses Apple
tooling to finish the device image. Discussion on the PR describes a pipeline
roughly equivalent to:

```text
D device code
    ↓
LDC / LLVM IR with Apple AIR metadata
    ↓
bitcode compatibility conversion
    ↓
Apple metallib tooling
    ↓
.metallib
```

This work is worth watching because it tests whether DCompute's existing
front-end contract can survive a third, structurally different GPU backend.
It should not yet be treated as a stable dependency.

## 3. GCC offloading machinery

ICK is GCC-derived, so GCC's existing offload architecture is at least as
important as LDC.

User documentation:

- https://gcc.gnu.org/onlinedocs/gcc/OpenMP-and-OpenACC-Options.html

GCC can be configured with offload targets and accepts target-specific
offload options. Current documented examples include:

- `nvptx-none`;
- `amdgcn-amdhsa`.

The relevant interface includes `-foffload` and
`-foffload-options=<target>=...`.

GCC internals also expose explicit offload hooks, including recording symbols
that must appear in the device function/variable table and serializing target
options into LTO/offload state:

- https://gcc.gnu.org/onlinedocs/gccint/Misc.html

The NVPTX libgomp implementation documentation is here:

- https://gcc.gnu.org/onlinedocs/libgomp/nvptx.html

This is not evidence that ordinary GDC source can already be marked and
offloaded. GCC's public OpenMP/OpenACC documentation describes those language
extensions for C, C++, and Fortran.

### Why this still matters to ICK

GDC uses the DMD-derived D front end and GCC back end:

- https://gcc.gnu.org/onlinedocs/gdc/D-Implementation.html

GCC internals also have D-specific target hooks:

- https://gcc.gnu.org/onlinedocs/gccint/Target-Structure.html

So there are two separable problems:

1. **D language semantics:** identify kernels/device functions, validate the
   device-safe subset, represent address spaces, and define host/device data
   behavior.
2. **Device compilation and packaging:** clone/partition the relevant IR,
   target NVPTX or AMDGCN, produce device images, and connect them to a host
   runtime.

LDC/DCompute is strong prior art for (1). GCC is strong prior art for (2).

A likely investigation for this branch is whether ICK can expose a
DCompute-like target-independent semantic layer while feeding the resulting
device region into GCC's existing offload machinery rather than inventing a
second complete GPU toolchain inside the GCC-derived compiler.

That is a hypothesis to test, not yet a chosen implementation.

## 4. Bindings are not compiler prior art

There are D packages that bind CUDA or OpenCL host APIs. The D ecosystem's
"awesome-d" list, for example, names DCompute alongside CUDA/OpenCL binding
projects:

- https://github.com/dlang-community/awesome-d#parallel-computing

Those bindings matter for host runtime integration, but they are a different
thing from translating D functions into device code. They should not be used
as evidence that the compiler problem is already solved.

## 5. Implications for ICK's target model

The GPU work should preserve the existing ICK rule that target dimensions are
orthogonal.

A GPU backend is not the same thing as a host operating system or package
format. At minimum the design should keep these separate:

- host instruction set / ABI;
- device architecture or portable device IR;
- device execution environment (CUDA, OpenCL, Vulkan compute, Metal, etc.);
- address-space model;
- host/device transfer or shared-memory model;
- device image container/embedding policy.

The source language should preferably expose target-independent concepts such
as "kernel", "device-safe function", and memory/address space. NVPTX, AMDGCN,
SPIR-V, or AIR should remain lowering choices unless a program explicitly asks
for a target-specific intrinsic.

That is consistent with the existing ICK target model in
[`docs/targets.md`](targets.md).

## 6. Questions for the next research pass

1. Inspect GCC's current offload source path in detail: `mkoffload`, LTO
   sections, libgomp plugin contracts, NVPTX, and AMDGCN.
2. Determine whether the current GDC front end can mark arbitrary D functions
   for GCC offload without adopting OpenMP/OpenACC syntax, or whether a new D
   UDA/pragma-to-GIMPLE seam is required.
3. Trace LDC's `@compute` representation from D semantic analysis through
   LLVM function/module emission and identify the smallest concepts worth
   reusing rather than copying LDC machinery.
4. Compare CUDA/NVPTX and SPIR-V address-space mappings against GCC's NVPTX and
   AMDGCN address-space conventions.
5. Decide whether ICK wants:
   - separate device images plus host runtime registration;
   - embedded device images in the host artifact;
   - or both.
6. Add a minimal acceptance target: one D `saxpy`-style kernel compiled from
   ICK source to inspectable device assembly/IR before any runtime launch work.
7. Keep specialized numeric/geometric types target-independent. Types such as
   low-precision floats, quaternions, projective coordinates, or rotation
   groups should enter the shared IR with semantics intact; each GPU backend
   can choose native instructions, vector lowering, library expansion, or
   scalarization.

## Sources checked in this pass

Direct D → GPU:

- https://github.com/libmir/dcompute
- https://github.com/libmir/dcompute/tree/master/docs
- https://github.com/ldc-developers/ldc/blob/master/runtime/druntime/src/ldc/dcompute.d
- https://github.com/ldc-developers/ldc/blob/master/gen/semantic-dcompute.cpp
- https://github.com/ldc-developers/ldc/blob/master/driver/dcomputecodegenerator.h
- https://github.com/ldc-developers/ldc/blob/master/driver/dcomputecodegenerator.cpp
- https://github.com/ldc-developers/ldc/blob/master/tests/codegen/dcompute_dual_targets.d
- https://github.com/ldc-developers/ldc/blob/master/CHANGELOG.md
- https://github.com/ldc-developers/ldc/pull/5118

GCC/GDC:

- https://gcc.gnu.org/onlinedocs/gdc/D-Implementation.html
- https://gcc.gnu.org/onlinedocs/gcc/OpenMP-and-OpenACC-Options.html
- https://gcc.gnu.org/onlinedocs/gccint/Misc.html
- https://gcc.gnu.org/onlinedocs/gccint/Target-Structure.html
- https://gcc.gnu.org/onlinedocs/libgomp/nvptx.html
