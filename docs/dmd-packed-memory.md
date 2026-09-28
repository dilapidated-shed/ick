# Packed memory in Icky DMD

This slice keeps the stored representation and the arithmetic representation
separate. E5M3 and E3M2 coordinates occupy one byte each. The first arithmetic
carrier is the existing `Float16` semantic type, whose machine carrier remains
binary32 in the portable scalar implementation.

“Just in time” means that a coordinate is decoded when the current arithmetic
operation consumes it in ahead-of-time compiled code. It does not mean a
runtime compiler or a new JIT. A call consumes only its requested coordinates;
the implementation does not construct a widened F16/F32 input array.

## Public scalar surface

```d
auto result = compute_at!(Float16, "*")(left, left_index, right, right_index);
bool stored = try_store_at(destination, index, result);
```

`compute_at` accepts read-only contiguous E5M3 and E3M2 slices, including mixed
representations, and supports `+`, `-`, `*`, and `/`. It checks both indices,
loads each packed coordinate once, decodes both values, converts them to
`Float16`, performs one binary32 operation under the existing Float16 contract,
and requantizes the result at that operation boundary. An invalid index triggers
an explicit non-returning failure before either coordinate is read. The public
result is one `Float16`, never a slice.

`try_store_at` checks the destination index before reading or writing the
coordinate. E3M2 keeps its existing total quantizer, including saturation,
NaN-to-positive-zero behavior, and unused-bit normalization. E5M3 has a partial
input domain: a rejected encode returns `false` and leaves the destination byte
unchanged.

E5M3 is unsigned Ootomo–Naruse storage, not signed IEEE FP8. Its codes 0–247
convert to finite Float16 values. Codes 248–255 convert to positive Float16
infinity because their decoded binary32 midpoints exceed the finite Float16
range. No valid E5M3 storage code is rejected during widening, and direct
E5M3 arithmetic remains unavailable.

## Compiler seam

The owned DMD recognizes the exact public compute_at and try_store_at
templates in module icky.packed_memory, including supported template arguments
and checked signatures. A same-named function in another module uses normal D
lowering.
The request in `dmd/packedmemory.d` retains:

- source representation for each operand;
- arithmetic representation and exact operation;
- destination representation;
- decode, arithmetic, encode, and packed-load/store stages;
- Float16 per-operation rounding;
- partial-domain versus total-quantization behavior;
- base, length, index, element stride, alignment, alias, effect, and ordering facts;
- the absence of a proven disjoint-alias relation; and
- the obligation that temporary widening stays bounded independently of vector length.

The compiler records and validates the full operation before ordinary call
lowering, then selects its bounded scalar body as the conservative follower.
That body checks indices before access, loads one coordinate from each source,
uses the existing codecs and Float16 operators, and returns or stores one
scalar. Its internal packed byte loads and stores reach the concrete DMD
memory followers. No step constructs a widened input array.

The public declarations and internal scalar helpers use
`pragma(inline, false)` so `-O -inline` cannot erase the operation boundary before
the request reaches DMD. Compiler receipts distinguish the semantic request
from follower execution; the optimized qualification requires both. Taking a
function address still emits and calls the same bounded scalar body.

Bounded scalar spills are allowed. Register allocation is a backend decision;
this contract does not require values to remain in registers. Whole-array
implicit widening remains forbidden.

## Deliberately unoptimized

This implementation is a correctness baseline. It does not claim native FP16
arithmetic or any throughput improvement. It chooses no SIMD or packed-fetch
width, prefetch distance, cache policy, non-temporal access, unroll factor,
independent-stream count, processor dispatch, memory-channel policy, or
microarchitecture-specific instruction. Those decisions belong to the later
measured x86 backend work.
