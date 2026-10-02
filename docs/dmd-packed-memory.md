# Packed memory in Icky DMD

This slice keeps stored representation and arithmetic representation separate.
`UE5M3` and `E3M2` coordinates occupy one byte each. Arithmetic is selected
explicitly per operation: the current scalar surface supports `Float16` and
signed `E5M3`.

No operation constructs a widened input array. A coordinate is decoded only
when the current ahead-of-time compiled scalar operation consumes it.

## Public scalar surface

```d
auto signed_result =
    compute_at!(E5M3, "-")(left, left_index, right, right_index);

auto half_result =
    compute_at!(Float16, "*")(left, left_index, right, right_index);

bool stored = try_store_at(destination, index, signed_result);
```

`compute_at` accepts read-only contiguous `UE5M3` and `E3M2` slices,
including mixed storage representations, and supports `+`, `-`, `*`, and
`/`. It checks both indices and loads each requested packed coordinate once.

With `Arithmetic == E5M3`, each input is converted into signed E5M3 and the
operation executes under the direct E5M3 contract in
`docs/signed-e5m3.md`. In particular, subtraction may return a negative E5M3
value. It does not silently select Float16. E5M3 supports `+` and `-` here,
using exact integer units of the minimum subnormal and one final E5M3 rounding.

Multiplication and division are the explicit promotion boundary:
`compute_at!(E5M3, "*")` and `compute_at!(E5M3, "/")` are rejected.
Callers select `compute_at!(Float16, "*")` or
`compute_at!(Float16, "/")` when those operations are required.

`try_store_at` accepts either arithmetic type. `E3M2` keeps its existing
total quantizer. `UE5M3` is positive-only storage: values outside its encoder
domain—including a negative E5M3 result—return `false` and leave the
destination byte unchanged. That failure is the explicit result/domain rule;
no hidden widening changes the result type.

The highest UE5M3 codes represent positive values larger than signed E5M3's
finite range. Converting such an operand to E5M3 therefore produces positive
infinity under the E5M3 conversion rule. The storage value itself remains
valid UE5M3.

## Compiler seam

The owned DMD recognizes the exact `compute_at` and `try_store_at` templates
in `icky.packed_memory`. The target-independent request retains the storage
type, arithmetic type, operation, result/store domain, memory facts, and
rounding boundary.

The trace distinguishes:

```text
rounding=Float16-per-operation
rounding=E5M3-per-operation
```

The conservative follower validates that the chosen rounding mode matches the
arithmetic representation before executing the ordinary scalar body. Internal
packed byte reads/stores also retain that arithmetic identity. A same-named
function outside `icky.packed_memory` receives ordinary D lowering.

The public declarations and scalar helpers use `pragma(inline, false)` so
`-O -inline` cannot erase the compiler seam before it is recorded. Function
pointers still execute the same bounded scalar fallback.

## Storage naming

`UE5M3` is the one-byte unsigned Ootomo–Naruse storage codec that earlier ICK
work called `E5M3`. Signed `E5M3` has nine meaningful bits and is a numeric
arithmetic type. Its ordinary scalar representation uses a 16-bit container.
Packing a stream densely at nine bits per value is a separate storage codec and
is not implied by `E5M3[]`.

## Deliberately unoptimized

This remains a correctness baseline. It makes no SIMD-width, prefetch, cache,
unroll, dispatch, or microarchitecture claim. Those are later backend choices.
