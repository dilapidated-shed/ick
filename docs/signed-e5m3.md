# Signed E5M3

Signed `E5M3` is a numeric arithmetic format distinct from the positive-only
one-byte `UE5M3` storage codec.

## Logical format

```text
s eeeee mmm
```

The logical width is nine bits: one sign bit, five exponent bits, and three
fraction bits. The exponent bias is 15.

For sign `s`, exponent field `E`, and fraction field `M`:

```text
E = 0, M = 0      (-1)^s 0
E = 0, M != 0     (-1)^s M * 2^-17
1 <= E <= 30      (-1)^s (8 + M) * 2^(E - 18)
E = 31, M = 0     (-1)^s infinity
E = 31, M != 0    NaN
```

The minimum positive subnormal is `2^-17`, the minimum normal is `2^-14`,
and the maximum finite value is 61440. Arithmetic canonicalizes NaN to code
`0x0fc`.

The scalar D value uses a `ushort` container with only the low nine bits
meaningful. This is not a claim that signed E5M3 occupies one byte. A dense
nine-bit array codec is a separate storage representation.

## Rounding

`+` and `-` return E5M3 and round once using round-to-nearest,
ties-to-even. No Float16 or binary32 arithmetic carrier is part of either
operation. Multiplication and division are intentionally not E5M3 operators;
code must select a wider arithmetic format explicitly for those operations.

The underflow tie at `2^-18` rounds to zero. The overflow midpoint is 63488:
values below it round to the maximum finite value when appropriate; an exact
63488 tie rounds to infinity because the conceptual next significand is even.

## Arithmetic

Addition and subtraction convert finite operands to exact signed integer units
of `2^-17`, perform the integer operation, and requantize to E5M3.

Multiplication and division are the promotion boundary. In packed code this
means selecting `compute_at!(Float16, "*")` or
`compute_at!(Float16, "/")`; an E5M3 multiply/divide instantiation is
rejected.

Addition/subtraction special values follow these explicit rules:

- opposite infinities added together are NaN;
- exact finite cancellation produces positive zero;
- negative zero plus negative zero produces negative zero.

## UE5M3 storage boundary

`UE5M3` remains the one-byte unsigned Ootomo–Naruse storage representation.
It has no direct arithmetic operators.

Packed code may decode UE5M3 into E5M3 for a requested operation. Storing an
E5M3 result back to UE5M3 is checked: if the result is negative, zero,
infinite, NaN, or otherwise outside the UE5M3 encoder domain, the store fails
and preserves the destination byte. No implicit Float16 widening is used to
escape that domain rule.
