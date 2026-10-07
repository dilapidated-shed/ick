# MIRO C67 target map

ICK should not grow a `miro-c67` machine ABI. The device maps onto ICK's
independent target dimensions.

## Model/platform evidence

The MIRO C67 retail specification names a MediaTek Helio G36. MediaTek specifies:

```text
CPU          8 x Arm Cortex-A53
CPU width    64-bit
max clock    2.2 GHz
GPU          IMG PowerVR GE8320
```

The retail listing also reports Android 14, 4 GB physical RAM and 64 GB storage.

Sources:

- https://www.mediatek.com/products/smartphones/mediatek-helio-g36
- https://www.newegg.com/miro-c67-6-75-black/p/23B-00MN-00005

## Mapping onto ICK dimensions

Known from model/platform documentation:

```text
microarchitecture/tuning family   Cortex-A53
silicon capability                64-bit
operating environment             Android (retail listing: Android 14)
GPU family                        PowerVR GE8320
```

New physical application evidence (user report, 2026-10-06):

- [isomorphismes/pauli PR #23, “Drive Android orbital rendering with checked hydrogen states”](https://github.com/isomorphismes/pauli/pull/23)
- Pauli source: `5f9f8a0fc08e4d4dd978298f47112af0ad02f196`
- Executed arm64-v8a APK SHA-256:
  `4ed50964086a0ffbd80964c0ce3dbaaa76bb24a9dfdd1a1c64b63ba3d5cfeb7c`
- User-reported physical result: “installs / launches / runs on MIRO C67: PASS”.

This demonstrates that the physical C67 Android userspace accepts and executes
that arm64-v8a native package. The package used the Android NDK; it does not
prove physical ICK execution or performance. The report is additional to the
older PR body's `NOT RUN` statement, not inferred from its emulator results.

Still unknown **in this application receipt**:

```text
Android primary ABI               UNKNOWN
32-bit ABI list                   UNKNOWN
64-bit ABI list                   UNKNOWN (arm64-v8a package execution demonstrated)
kernel machine                    UNKNOWN
runtime page size                 UNKNOWN
physical ICK execution            NOT_VERIFIED
```

A 64-bit CPU alone does not establish userspace ABI support. The application
receipt now establishes arm64-v8a execution; it does not supply the complete
property lists, fingerprint, kernel machine or page size requested by
[ai-ci issue #196, “Collect a physical MIRO C67 ABI and native-runtime receipt”](https://github.com/isomorphisms/ai-ci/issues/196).
Other hardware records may supply separate receipts; do not reconstruct those
fields from the Pauli result. Existing MIRO A1 evidence does not transfer.

## Compiler consequence

ICK already keeps `arm64-v8a` and `armeabi-v7a` as separate Android ABI
qualification lanes. Use the existing arm64-v8a lane for this newly demonstrated
C67 package boundary. [Cortex-A53 qualification](../qualification/cortex-a53/README.md)
selects `-march=armv8-a -mtune=cortex-a53` while retaining
`-march=armv8-a -mtune=generic` as baseline. No device ABI is added.

Cortex-A53 optimization is a separate decision from ABI selection:

- keep the generic Android ABI output as the correctness baseline;
- add `cortex-a53` scheduling/instruction-selection tuning only as an explicit
  optimization mode;
- compare size and physical-device timing against the untuned baseline;
- do not let a device-specific tuning choice change the public Android calling
  convention;
- do not copy the MIRO A1 physical receipt or PowerVR GE8322 results onto C67.

## Physical qualification needed

Retain the exact C67 Android ABI list, kernel machine, page size, compiler
revision, artifact hash and physical execution result. Only then should C67 be
named as complete ICK runtime qualification for either existing Android ABI lane.
The Pauli receipt above remains valid, narrower package execution evidence.

Shared hardware evidence belongs in `isomorphisms/android-NDK/hardware/`.

## PowerVR boundary

ICK compiles CPU-side C for the Cortex-A53. GLES shaders pass through the Android
graphics stack and are compiled for IMG PowerVR GE8320 by the PowerVR driver.
ICK has no GE8320 machine-code backend: **Cortex-A53 tuning ≠ PowerVR GE8320 tuning**.
CPU instruction counts and timings do not establish GPU optimization.

Later GPU work needs exact GL renderer/vendor/version strings, GLES limits,
shader precision and extensions, shader compile/link results, GPU frame timing,
thermal behavior, and workload comparisons between CPU volume rendering and
GLES ray integration. The present qualification does not implement that renderer.
