# Target model

ICK should not encode a target as one tangled product name. A build target is the product of independent constraints.

## Independent dimensions

- **instruction set**: AArch64, ARMv7/Thumb-2, x86-64, x86, RISC-V, or another machine
- **machine ABI**: register use, argument/return convention, stack alignment, reserved registers, object format
- **operating environment**: Android, Linux, bare metal, or another system
- **OS/API floor**: for example an Android API level; this is not the same thing as the instruction set
- **C/runtime environment**: Bionic, another libc, freestanding, or no runtime
- **link/load constraints**: dynamic/static linkage, PIE/PIC, segment alignment, supported runtime page sizes
- **graphics capability**: no graphics, GLES 2, GLES 3, Vulkan, framebuffer, or another independently selected interface
- **package format**: APK, ELF executable, shared object, ROM image, or another container

The compiler front end should not know that Android happens to use a particular graphics API or page size. Back ends should not decide an Android API floor. Packaging should consume target facts rather than create them.

## Android CPU matrix

For the currently public Android NDK ABI set, keep four CPU/ABI targets independently qualifiable:

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`
- `x86`

A release may choose a subset, but the compiler should not make the omission structural.

## Android API floors

The selected NDK constrains the oldest Android API it can target. The current NDK lane and any old-Android lane must therefore be explicit, pinned build inputs.

The current release lane should first qualify the minimum supported by the pinned current NDK. Older Android support belongs in additional compatibility lanes using appropriately old, pinned NDKs; it must not require contaminating the current compiler target with historical assumptions.

## Runtime page size

Runtime page size is an operating-system property, not a CPU identity and not a proxy for device size. ICK should describe the maximum load-segment alignment its output satisfies and then test that the same artifact loads on the intended runtime page sizes.

Do not create separate `arm64-4k` and `arm64-16k` compiler back ends unless a real incompatibility requires separate code generation. Prefer one correctly aligned 64-bit Android object/shared library that is valid on both 4 KiB and 16 KiB systems. [Android's current NDK guidance](https://android.googlesource.com/platform/ndk/+/master/docs/BuildSystemMaintainers.md#page-sizes) applies the 16 KiB runtime boundary to `arm64-v8a` and `x86_64`; the 32-bit ABIs retain 4 KiB load alignment.

For systems without virtual-memory paging, such as many bare-metal and retro targets, this dimension can simply be absent.

## Graphics

Graphics capability is independent of CPU and Android version. If an application can render through GLES 2, it should be allowed to do so even when GLES 3 is unavailable. A GLES 3 path can remain an optional runtime-selected path rather than an installation requirement.

This separation is intentional: an exotic CPU target should not inherit Android assumptions, and an old Android target should not inherit a graphics requirement merely because a newer implementation happened to use it.
