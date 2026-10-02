# Indra's Pearls consumer

`isomorphismes/indras-pearls` is an Android Schottky-limit-set consumer of
the ARMv7 ICK C leaf-object boundary.

The application merge receipt is Indra's Pearls PR #5, merged as
`4da9e06226b9d7abd007067bdc231edf23dbd98b`.

Its qualification job pins ICK commit
`ea034a574097e81d1027660b39c3e1c185d11b80`, rebuilds the ICK C compiler
from the owned source plus pinned GCC reference, and compiles the real
Schottky mathematics producer with:

```text
arm-linux-gnueabi-gcc
  -march=armv7-a
  -mthumb
  -mfpu=neon
  -mfloat-abi=softfp
  -std=c11
  -O2
  -fPIC
  -ffreestanding
  -DINDRAS_FREESTANDING_MATH
```

The ICK-compiled translation units are:

- `android/app/src/main/cpp/mobius_math.c`
- `android/app/src/main/cpp/renderer_packet.c`

Android NDK r29 Clang/lld then links those objects with the NDK-side probe and
`libm` into an Android ARM32 shared object. The retained receipt verifies:

- `ELF32`;
- machine `ARM`;
- Android `armeabi-v7a` softfp-compatible object/link boundary;
- no unresolved definitions under `-Wl,-z,defs`;
- no text relocations under `-Wl,-z,text`;
- successful export of `indras_ick_renderer_packet_probe`.

The compiler boundary is deliberately ordinary C scalar/array data:
one `float` family parameter, integer status, and a flat float renderer
packet. C aggregates and any compiler-private complex representation stay
inside the producer translation units.

The mathematical source of truth remains the binary64 C Möbius/Schottky core.
It constructs a marked rank-2 group, derives and validates the four classical
isometric circles and exit maps, then narrows only the final renderer packet
to binary32 for GLES.

This consumer does not claim that ICK is the Android linker/sysroot driver or
that the whole NativeActivity/GLES application is ICK-compiled. It proves a
real application-owned C math path compiled by ICK and linked into the Android
NDK boundary.
