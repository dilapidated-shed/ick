# E3M2 and E5M3 storage types

ICK exposes the currently specified low-precision formats through
`<ick/imprecise.h>`.

They are deliberately distinct C types:

```c
typedef struct { ick_byte payload; } E3M2;
typedef struct { ick_byte payload; } E5M3;
```

Both occupy one byte in C objects.  They are storage types, not new C
arithmetic types.  Ordinary arithmetic on either type is therefore rejected by
C rather than silently promoted to an invented scalar arithmetic model.

## E3M2

ICK follows the OCP FP6 E3M2 element encoding documented in the Idric ARM
backend at commit
`a2e12da5fba7d499507807a8f394323fbeecbdcf`:

https://github.com/isomorphisms/idric-arm-thumb/blob/a2e12da5fba7d499507807a8f394323fbeecbdcf/specifications/e3m2.md

The low six payload bits contain one sign bit, three exponent bits, and two
mantissa bits.  The public boundary is:

```c
E3M2 e3m2_from_code(ick_byte);
ick_byte e3m2_code(E3M2);
E3M2 e3m2_from_float(float);
float e3m2_to_float(E3M2);
```

`e3m2_from_float` implements round-to-nearest, ties-to-even, signed zero,
subnormals, and saturation to the maximum finite magnitude.  The source
specification leaves NaN conversion implementation-defined; ICK maps a source
NaN to signed zero.  The two unused high bits of a byte are cleared at the
code boundary.

## E5M3

ICK follows the Ootomo-Naruse unsigned eight-bit storage format documented in
the Idric ARM backend at commit
`7c976d85e1b477d93c01db8f6392cffe117251d2`:

https://github.com/isomorphisms/idric-arm-thumb/blob/7c976d85e1b477d93c01db8f6392cffe117251d2/specifications/e5m3.md

This E5M3 has five exponent bits and three mantissa bits and no sign bit.  It
is not a signed 1+5+3 nine-bit float.  The public boundary is:

```c
E5M3 e5m3_from_code(ick_byte);
ick_byte e5m3_code(E5M3);
int e5m3_from_float(float, E5M3 *);
float e5m3_to_float(E5M3);
```

The published FP32-to-E5M3 rule is partial, so ICK keeps it partial.
`e5m3_from_float` returns 1 only for positive normal binary32 inputs whose
exponent lies in the non-wrapping E5M3 source range; it returns 0 and leaves
the output unchanged for zero, negative values, subnormals, infinities, NaNs,
out-of-range values, or a null output pointer.

`e5m3_to_float` is defined for all 256 payload codes and uses the published
midpoint reconstruction.

## Compiler boundary

The header requires an eight-bit byte and IEEE-like binary32 `float`. It is
freestanding and includes no libc headers; `ick_byte` and `ick_u32` are
defined from compiler-provided C types.  The
Android qualification matrix compiles the probe with each of ICK's four
qualified compiler targets.  A separate host semantic probe exhausts all 64
E3M2 codes and all 256 E5M3 codes and checks the E3M2 tie, saturation, NaN,
and signed-zero rules.

The one-byte object representation does not promise that a C ABI passes these
single-member structures exactly like `ick_byte`.  External ABI boundaries
should pass the payload code as `ick_byte` unless both sides deliberately
share the same structure ABI.
