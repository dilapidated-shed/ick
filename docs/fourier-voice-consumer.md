# Fourier Voice consumer

`isomorphismes/Fourier-sound` is the first MIRO A1 application consumer of
the ARMv7 Android leaf-object boundary on this line.

The consumer branch is `ick/fourier-voice-miro-a1`. It pins ICK commit
`2176498723bf01792236cef3bebf349822cae496`, rebuilds the compiler from the
owned ICK source plus the pinned GCC reference, and compiles the Fourier Voice
polynomial evaluator with:

```text
arm-linux-gnueabi-gcc
  -march=armv7-a
  -mthumb
  -mfpu=neon
  -mfloat-abi=softfp
  -O2
  -fPIC
  -ffreestanding
  -nostdinc
```

The ICK object is then linked into the application's native
`libfourier_voice.so` by the Android NDK linker. The packaged application has
no DEX.

The cross-compiler boundary deliberately uses only scalar and array C data.
No ICK `_Complex` representation crosses into NDK-Clang code. The ICK-owned
polynomial evaluator is used in the real pixel-rendering path, while the
ordinary C evaluator remains present for a startup hardware cross-check.

This consumer does not yet claim that ICK is a complete Android driver or that
the whole Fourier Voice shared library is ICK-compiled. It extends the
qualification from an isolated runtime fixture to an application-owned,
continuously exercised math leaf inside an APK.
