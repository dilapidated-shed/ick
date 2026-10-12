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

Unary `-` flips the sign bit of every non-NaN value, including zero and
infinity. It canonicalizes any NaN input to `0x0fc`. The named numeric
predicates `equal` and `less` compare the nine-bit values without a
binary32 or Float16 carrier. Both return false for an unordered NaN operand;
`+0` and `-0` compare equal and neither is less than the other. Neither
method asserts a total ordering of NaNs.

The present D implementation is a nominal two-byte struct; its default
`.init` is the all-zero payload (`+0`). This does **not** implement or
supersede a future primitive-language floating type's NaN initializer.

## Independent qualification

`dmd/qualification/representations/oracle.c` separately computes signed
addition/subtraction in exact integer units of `2^-17`. It chooses the
nearest output code by binary-searching finite adjacent-code midpoints
(including the conceptual infinity successor of maximum finite), with
ties to even. The D acceptance test checks all `512 × 512` ordered
operand pairs for `+`, `-`, `equal`, and `less`, plus negation of
all 512 payloads. The C oracle never computes the expected answer with a
binary32 arithmetic operation or by calling the D quantizer.

Passing these host tests does not establish compiler-native primitive E5M3,
ARM code generation, or physical Android acceptance.

## UE5M3 storage boundary

`UE5M3` remains the one-byte unsigned Ootomo–Naruse storage representation.
It has no direct arithmetic operators.

Packed code may decode UE5M3 into E5M3 for a requested operation. Storing an
E5M3 result back to UE5M3 is checked: if the result is negative, zero,
infinite, NaN, or otherwise outside the UE5M3 encoder domain, the store fails
and preserves the destination byte. No implicit Float16 widening is used to
escape that domain rule.
