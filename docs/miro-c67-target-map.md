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

Still physically unverified:

```text
Android primary ABI               UNKNOWN
32-bit ABI list                   UNKNOWN
64-bit ABI list                   UNKNOWN
kernel machine                    UNKNOWN
runtime page size                 UNKNOWN
physical ICK execution            NOT_VERIFIED
```

A 64-bit CPU does not prove that the installed Android userspace exposes
`arm64-v8a`, and existing MIRO A1 `armeabi-v7a` evidence does not transfer to
the C67.

## Compiler consequence

ICK already keeps `arm64-v8a` and `armeabi-v7a` as separate Android ABI
qualification lanes. Once a physical C67 receipt identifies its supported ABI,
use the existing lane.

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
named as runtime evidence for either existing Android ABI lane.

Shared hardware evidence belongs in `isomorphisms/android-NDK/hardware/`.
