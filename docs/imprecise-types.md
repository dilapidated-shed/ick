# Imprecise numeric types

ICK exposes the same five low-precision numeric concepts currently defined by
the Idriç/Edriç source layer:

- `Float16`
- `E4M3`
- `E5M2`
- `E3M2`
- `E5M3`

The C boundary lives in `<ick/imprecise.h>`. The header is freestanding: it
uses no libc headers and requires only an eight-bit byte, a 32-bit unsigned
integer type, and IEEE-like binary32 `float`.

## Storage

```text
Float16   16 bits
E4M3       8 bits
E5M2       8 bits
E3M2       6 payload bits in one byte
E5M3       8 bits
```

They are distinct C structure types rather than aliases for integer containers.
Raw payload access is explicit through the corresponding `*_from_code` and
`*_code` functions.

## Arithmetic policy

`Float16` arithmetic is binary16 arithmetic. The portable reference follower
operates on the 16-bit payload with integer significands, exponents, exact
dyadic alignment and round-to-nearest/ties-to-even. It does **not** decode to
binary32 to perform `+`, `-`, `*`, or `/`.

`E4M3`, `E5M2`, and `E3M2` still use the older reference policy for now:
decode to binary32, perform one operation, then requantize. That remaining
policy is intentionally separate from Float16 and E5M3.

`E5M3` keeps ordinary C operators unavailable because its unsigned storage
domain cannot represent zero, negative results, underflow, or overflow.
Checked `e5m3_add`, `e5m3_subtract`, and `e5m3_multiply` are provided
instead. Addition/subtraction use an exact common fixed-point lattice.
Multiplication widens only the integer significand product required by that
one operation, then immediately requantizes to E5M3. None of those operations
uses Float16 or binary32 arithmetic.

## Float16

`Float16` uses IEEE binary16 storage. Conversion from binary32 uses
round-to-nearest, ties-to-even, including subnormals and the normal overflow
boundary at 65520. Infinities remain infinities and NaNs remain NaNs; NaN
payloads are canonicalized by the storage conversion.

The payload and exceptional-value behavior remain IEEE binary16; the arithmetic
implementation is now independent of binary32 machine arithmetic.

## E4M3

ICK uses the OCP OFP8 E4M3 encoding: one sign bit, four exponent bits, and three
mantissa bits. The maximum finite magnitude is 448. Construction uses
round-to-nearest, ties-to-even and saturates finite/infinite overflow to the
maximum finite value. The reserved NaN encoding remains NaN.

## E5M2

ICK uses the OCP OFP8 E5M2 encoding: one sign bit, five exponent bits, and two
mantissa bits. The maximum finite magnitude used by the Idriç arithmetic policy
is 57344. Construction uses round-to-nearest, ties-to-even and saturates
finite/infinite overflow to that value. NaN remains NaN.

## E3M2

ICK follows the OCP MX FP6 E3M2 element encoding documented in the ARM Thumb
backend. The six payload bits are one sign bit, three exponent bits, and two
mantissa bits. E3M2 has subnormals and signed zero but no infinity or NaN
encoding. Overflow saturates at 28. A source NaN maps to positive zero, matching the current Idriç source policy.

## E5M3

ICK follows the Ootomo-Naruse unsigned storage format documented in the ARM
Thumb backend. The published conversion applies to positive normal binary32
inputs, so `e5m3_from_float` remains partial and returns failure for values
outside that domain. `e5m3_to_float` implements the published midpoint
reconstruction for every one of the 256 payload codes. Checked arithmetic
preserves the output argument on any result that falls outside this domain.

## Source alignment

The policy comes from the current Idriç work:

- PR #49: original Float16 source surface
- PR #120: first-class E4M3, E5M2, E3M2, and E5M3 source semantics

ICK no longer adopts binary32 as the Float16 arithmetic carrier. That is an
implementation-policy correction in this repository, not a storage-format
change.

The E3M2 and E5M3 storage references are also recorded in
`isomorphisms/idric-arm-thumb`.

## Qualification

The host semantic probe checks:

- every 65,536 Float16 payload;
- every finite positive E4M3 payload;
- every finite positive E5M2 payload;
- all 64 E3M2 payloads;
- all 256 E5M3 payloads;
- representative overflow and tie boundaries;
- Float16 `+`, `-`, `*`, and `/` against the C/D semantic receipts;
- exhaustive checked E5M3 `+`, `-`, and `*` result/domain behavior;
- the remaining E4M3/E5M2/E3M2 requantization policy.

The Android four-ABI matrix then compiles the same freestanding interface with
ICK itself and verifies that no binary64 helper has entered the boundary.
