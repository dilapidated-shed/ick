# ARMv7 NEON FFT qualification

Fourier-style workloads need more than an ARMv7 object that merely advertises
NEON as an available target feature. ICK must lower real vector arithmetic to
actual Advanced SIMD instructions.

`ick-armv7-neon-fft.c` is a four-lane radix-2 complex butterfly kernel. It
uses GCC's 16-byte vector type internally but keeps the externally visible ABI
to ordinary `float *` and integer parameters, so no compiler-specific vector
type crosses the Android NDK boundary.

The Android ABI workflow compiles the kernel for `armeabi-v7a` with:

```text
-march=armv7-a -mthumb -mfpu=neon -mfloat-abi=softfp -O3 -funsafe-math-optimizations
```

The gate requires all of the following:

- generated assembly performs binary32 multiply, add, and subtract on NEON
  Q registers, proving four-lane SIMD rather than scalar VFP;
- the object records the ARMv7 NEON architecture attribute;
- the Android softfp calling convention remains in force.

This is intentionally a compiler/code-generation qualification, not an FFT
library API. Fourier Voice can keep its FFT algorithm separately and use this
receipt to know that an explicit four-lane butterfly has a qualified NEON
lowering on `armeabi-v7a`.

The relaxed floating-point flag is local to this explicit SIMD qualification
kernel. It is the numerical policy that permits ARMv7 NEON binary32 arithmetic:
NEON can flush subnormals rather than preserving strict scalar IEEE behavior.
The ordinary ARM32 qualification and ICK's general floating-point policy remain
strict, and this gate does not ask the compiler to auto-vectorize ordinary
scalar float loops.

Compact formats such as E5M3 remain governed by their separate arithmetic and
storage contract. This gate proves the SIMD machine path without changing that
contract.
