# ARMv7 NEON FFT qualification

Fourier-style workloads need more than an ARMv7 object that merely advertises
NEON as an available target feature. ICK must be able to turn the arithmetic
of an FFT stage into actual Advanced SIMD instructions.

`ick-armv7-neon-fft.c` is a small radix-2 complex butterfly kernel. It keeps
the externally visible ABI to ordinary `float *` and integer parameters, so
no compiler-specific vector type crosses the Android NDK boundary.

The Android ABI workflow compiles the kernel for `armeabi-v7a` with:

```text
-march=armv7-a -mthumb -mfpu=neon -mfloat-abi=softfp
-O3 -ftree-vectorize -fno-vect-cost-model
```

The gate requires all of the following:

- GCC's vectorizer reports a 16-byte vectorized loop (four binary32 lanes).
- generated assembly contains NEON binary32 multiply, add, and subtract
  arithmetic;
- the object records the ARMv7 NEON architecture attribute;
- the Android softfp calling convention remains in force.

This is intentionally a compiler/code-generation qualification, not an FFT
library API. Fourier Voice can keep its FFT algorithm separately and use this
receipt to know that an ordinary float butterfly loop has a qualified NEON
lowering on `armeabi-v7a`.

Compact formats such as E5M3 remain storage representations. The active FFT
butterfly in this qualification is binary32; low-precision unpack/pack policy
can be optimized independently without weakening the numerical kernel.
