# Packed memory in Icky DMD

This slice keeps stored representation and arithmetic policy separate. E5M3
and E3M2 coordinates occupy one byte each. E5M3 addition/subtraction and narrow
multiplication now have a checked path that stays in the E5M3 dyadic lattice.
Float16 is used only when a caller explicitly requests a wider result, and its
portable arithmetic implementation now follows binary16 semantics directly
rather than using binary32 as a machine arithmetic carrier.

“Just in time” means that a wider representation is created only for an
operation whose public surface explicitly requests it. It does not mean a
runtime compiler or a new JIT. A call consumes only its requested coordinates;
the implementation never constructs a widened F16/F32 input array.

## Public scalar surface

```d
E5M3 narrow;
bool accepted = try_e5m3_at!("+")(left, left_index, right, right_index, narrow);

auto wider = compute_at!(Float16, "*")(left, left_index, mixed, right_index);
bool stored = try_store_at(destination, index, wider);
```

`try_e5m3_at` accepts two E5M3 slices and supports checked `+`, `-`, and
narrow `*`. It reads only the requested scalars. Addition/subtraction use an
exact common fixed-point lattice; multiplication uses only the wider integer
significand product needed for that one operation. A bounds or E5M3-domain
failure returns `false` and leaves the output unchanged.

`compute_at!(Float16, ...)` remains the explicit widening surface for E5M3/E3M2
and mixed-format work. E5M3/E5M3 `+` and `-` are intentionally excluded from
that overload so they cannot silently widen. Its Float16 arithmetic is binary16
round-to-nearest/ties-to-even and no longer performs the operation in binary32.
An invalid index on this explicit widening surface still triggers a non-returning
precondition failure before either coordinate is read.

`try_store_at` checks the destination index before reading or writing the
coordinate. E3M2 keeps its existing total quantizer, including saturation,
NaN-to-positive-zero behavior, and unused-bit normalization. E5M3 has a partial
input domain: a rejected encode returns `false` and leaves the destination byte
unchanged.

E5M3 is unsigned Ootomo–Naruse storage, not signed IEEE FP8. Its checked
arithmetic therefore has a partial result domain: zero/negative subtraction,
underflow and overflow are reported as failure rather than inventing a signed
or zero encoding. The ordinary `E5M3 + E5M3` operator remains unavailable for
that reason.

## Compiler seam

The owned DMD recognizes the exact public compute_at and try_store_at
templates in module icky.packed_memory, including supported template arguments
and checked signatures. A same-named function in another module uses normal D
lowering.
The request in `dmd/packedmemory.d` retains:

- source representation for each operand;
- arithmetic representation and exact operation;
- destination representation;
- decode, arithmetic, encode, and packed-load/store stages for the explicit widening surface;
- Float16 per-operation binary16 rounding;
- partial-domain versus total-quantization behavior;
- base, length, index, element stride, alignment, alias, effect, and ordering facts;
- the absence of a proven disjoint-alias relation; and
- the obligation that temporary widening stays bounded independently of vector length.

The compiler records and validates the full operation before ordinary call
lowering, then selects its bounded scalar body as the conservative follower.
That body checks indices before access, loads one coordinate from each source,
uses the existing codecs and Float16 operators, and returns or stores one
scalar. The direct E5M3 checked surface currently uses ordinary D scalar
lowering over the exact E5M3 integer arithmetic, while its memory access remains
bounded to the addressed elements. No step constructs a widened input array.

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
