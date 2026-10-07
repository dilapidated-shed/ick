# Sun F03: FP16-positioned signed E5M3 experiment

Recommendation: **retain as an alternate execution representation; do not
adopt as the default**. Host semantics pass, but ARM/Thumb generated code and
timing are still blocked. This is an incomplete ARM experiment, not an ARM
performance result.

## Representation and semantics

`icky.experimental.e5m3_left.LeftE5M3` holds `(logical_code & 0x01ff) << 7`
in a private `ushort`. Its size is two bytes, identical to `E5M3`.
Its sign is bit 15, exponent is bits 14–10, fraction is bits 9–7;
bits 6–0 are always zero. Raw storage admission rejects malformed low bits
and preserves the destination. Arrays remain two bytes per element; this
experiment adds neither dense nine-bit packing nor SIMD primitives.

The authoritative numerical contract stays in [signed-e5m3.md](signed-e5m3.md).
Direct addition/subtraction convert to the existing right-aligned E5M3 type,
use its exact-dyadic arithmetic, then restore the alternate layout. They do
not use FP16 arithmetic. This intentionally conservative lane exposes the
cost of crossing into the existing arithmetic implementation; it does not
measure a newly optimized left-layout integer adder.

Widening returns `Float16.from_code(payload)`, preserving bits without a shift.
Narrowing rounds the discarded seven FP16 fraction bits to nearest, ties to
even, including subnormal/normal carry and finite/infinity overflow. FP16
NaNs become the contract's positive canonical E5M3 NaN, `0xfc << 7`.
Raw widening retains NaN payloads; numeric conversion may canonicalize them.

Direct E5M3 multiplication remains rejected. The explicit experiment helper
widen → established Float16 multiply → E5M3 narrow retains the existing
promotion boundary, including both rounding steps. It is not a newly defined
E5M3 multiplication operator. Comparisons are experimental numeric predicates,
with unordered NaNs and equal signed zeros, checked against decoded values.

## Exhaustive host qualification

The owned IDK compiler built from base
`45a65d8b8c8928843b1bdaa1e737ce8b5ae814e0` compiled and executed both debug
and `-O -inline` BetterC qualifications. Both passed:

- all 512 logical encodings: exact decode, FP16 payload, sign and negation;
- all 65,536 storage words: accept exactly the 512 canonical words, preserve
  the output on rejection;
- all 65,536 FP16 encodings: alternate and matched right-layout narrowing
  agree with the established E5M3 conversion, including NaN normalization;
- all 262,144 ordered pairs: add, subtract, explicit promoted multiplication,
  and six numeric comparisons; every result has zero low seven bits;
- 1,488 binary32 inputs: predecessor, midpoint and successor for every
  positive finite rounding boundary, including underflow and overflow, for
  both signs. Expected tie outcomes are derived from code parity.

Addition/subtraction comparisons deliberately reuse the established numerical
implementation: they prove representation transport, not an independent proof
of that implementation's arithmetic. The midpoint checks are an independent
rounding oracle. FP16 exhaustiveness covers every representable FP16 input on
both sides of those boundaries.

## ARM/Thumb boundary comparison

`dmd/qualification/e5m3-left/layout-thumb.S` preserves handwritten Thumb-2
probes. They are **unassembled and unexecuted**, and are not compiler-generated
Idriç/IDK evidence. The instruction counts below exclude the return:

| Boundary | Right-aligned | Left-aligned |
|---|---|---|
| Load FP16-positioned payload | `ldrh; lsls #7` (2) | `ldrh` (1) |
| Load code for unchanged integer adder | `ldrh` (1) | `ldrh; lsrs #7` (2) |
| Store canonical result code | `strh` (1) | `lsls #7; strh` (2) |
| Narrow arbitrary FP16 | shared RNE bit quantizer, then `lsrs #7` | shared RNE bit quantizer |

For two inputs and one output, using the unchanged integer adder adds two
right shifts and one left shift to the alternate lane. In an explicitly
FP16-promoted multiply/store path, the alternate lane can instead remove two
input shifts and the final code-repositioning shift. Rounding, NaN handling,
and storage validation remain obligations in either representation. The
handwritten narrowing wrapper uses a call and stack save for convenience;
that wrapper overhead is not an intrinsic layout cost. The shared quantizer
uses scratch r2/r3; actual register pressure and code size need target emission.

The owned IDK compiler rejects `-mtriple=armv7a-linux-androideabi21` with exit
1 and an unrecognized-switch diagnostic. No qualified ARM/Thumb generator
for this signed IDK scalar was available in the selected lane. The historical
`fuego-ironworks/idric-arm-thumb` repository's current `main` owns DEX and
explicitly excludes ARM implementation paths. Moving this experiment onto DEX
or importing unrelated compiler backend work would violate its scope.

The inspected ARM development branch `fix/compact-promotion-boundary`, head
`185f3ecb0d5fbd5e4a363b77ec4512e09d0dcf56`, still defines `OotomoE5M3` as
unsigned storage conversion and rejects arithmetic in
`src/Backend/ARMThumb/Emit.idr`. Its scalar helper uses the unsigned codec.
Substituting it for the signed nine-bit type would change semantics. The
required target gap is signed E5M3 admission and lowering, not merely finding
an ARM assembler.

## Benchmark method and interpretation

`dmd/qualification/e5m3-left/benchmark.d` measures six separately instantiated
kernels: 0 sequential raw loads, 1 load/widen, 2 load/add, 3 32 immediate-rounded
additions per element, 4 load/explicit-FP16-multiply/narrow/store, and 5
widen/narrow/store. Arrays have 256, 16,384 and 1,048,576 elements, seven timed
samples per layout/kernel/size. A further streaming tier uses 33,554,432
elements and three samples: 64 MiB input exceeds the observed 32 MiB host L3;
store kernels have a 128 MiB working set. The repeated-add kernel uses the
smaller tiers to avoid conflating arithmetic cost with this streaming test.

Allocation and initialization precede timing; each sample warms its kernel,
uses a monotonic clock, and verifies checksums. Order alternates by sample.
Stored outputs are consumed after timing; cross-layout logical checksums must
also match. Inputs are deterministic positive finite codes 1–240. Exceptional
values and signs are exhaustively qualified, but not performance workloads.
Modulo indexing and shared arithmetic calls can dominate some kernels.
Measurements are a single shared-container campaign, not confidence intervals.

Both layouts use the same bit-rounding algorithm when narrowing FP16. The
right-layout control is tested against the existing `E5M3.from_float` codec;
using its slower general binary32 conversion only on the right would confound
quantizer optimization with layout choice. Production `E5M3` remains unchanged.

Host: Ubuntu 24.04.3, x86-64, AMD EPYC 9V74; compilation uses the rebuilt IDK
DMD 2.113.0. LDC 1.36.0 bootstraps that compiler only; it is not the consumer
compiler. Host measurements cannot establish performance on MIRO A1, C67,
Thumb or ARM. Raw results, medians and generated x86 kernel bodies are in
`dmd/qualification/e5m3-left/results/`.

Streaming tier (three samples per layout):

| Streaming kernel | Right median | Left median | Left/right |
|---|---:|---:|---:|
| Sequential load | 20.49 ms | 20.36 ms | 0.994 |
| Load/widen | 20.63 ms | 20.36 ms | 0.987 |
| Load/add | 707.36 ms | 723.34 ms | 1.023 |
| Multiply/store | 488.45 ms | 444.88 ms | 0.911 |
| Conversion/store | 124.85 ms | 94.63 ms | 0.758 |

The table is host diagnostic evidence only. In this campaign the streaming
add path costs about 2.3% more, multiply/store costs about 8.9% less, and
conversion/store costs about 24.2% less. At 1,048,576 elements the repeated-add
kernel is approximately tied (left/right 1.004). Tiny differences in a shared
container should not be treated as established microarchitectural effects.

Static x86 instruction counts include prologues and loops but exclude callees;
they are not dynamic instruction counts. Shared arithmetic, FP16 codec, and
quantizer bodies must be included when assessing total execution cost.
No packed SIMD instructions appear in the inspected kernel bodies.

The generated x86 widening loop for the alternate layout uses a stack store
and reload; the right-layout loop uses a shift and mask without that spill.
Eliminating a shift in source therefore does not ensure cheaper execution.

## Remaining acceptance

| Deliverable | State |
|---|---|
| Alternate type and existing layout preserved | COMPLETE |
| Exhaustive cross-layout host tests | COMPLETE |
| Generated x86 body/size comparison | COMPLETE |
| Host timing and large-array streaming benchmark | COMPLETE |
| Handwritten Thumb boundary comparison | COMPLETE, static source only |
| ARM/Thumb generated code, actual code size and register costs | BLOCKED: no qualified target generator in selected IDK lane |
| ARM/Thumb runtime and physical-phone timing | NOT_RUN |
| Default representation adoption | REJECTED for now: evidence incomplete |

Retain the experiment until a qualified target can run both layouts with the
same arithmetic policy. Adopt only if important target paths improve without a
compensating regression. Host conversion wins alone do not meet that condition.
