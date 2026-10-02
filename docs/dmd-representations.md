# Specialized representations in the Mars/DMD line

## What exists in this slice

`dmd/library/icky/imprecise.d` and `dmd/library/icky/circle.d` are native,
allocation-free D value types for use with the owned DMD compiler. They need
no C implementation at runtime, Java, Gradle, NDK, JNI or DEX. The C code in
qualification is an independent test oracle only.

The names are distinct nominal structure types. A name such as `E4M3` aliases
a particular structure-template instance, not `ubyte` or `float`; `E4M3` and
`E5M2` are different types even though both occupy one byte.

This is **not** a claim that new primitive type keywords or the backend seam
from issue #14 have been implemented. Ordinary D type checking preserves the
structure identities; ordinary D code generation implements the operations.
An explicit compiler representation-selection/lowering stage is still owed.

## Compact scalars

| Type | Storage | Arithmetic |
| --- | --- | --- |
| Float16 | 2 bytes, binary16 | Decode to binary32, one operation, requantize |
| E4M3 | 1 byte | Same, with the established E4M3 saturation/NaN policy |
| E5M2 | 1 byte | Same, with the established E5M2 saturation/NaN policy |
| E3M2 | 6 payload bits in 1 byte | Same; saturate at 28; source NaN becomes +0 |
| UE5M3 | 1 byte, unsigned Ootomo–Naruse storage | No direct arithmetic |
| E5M3 | 9 meaningful bits in a 16-bit scalar container | Signed `+`/`-` directly; multiply/divide require explicit Float16 |

UE5M3 ports the existing C `E5M3` Ootomo–Naruse byte codec from
`ick/include/ick/imprecise.h`; the D name makes its unsigned storage role
explicit. Signed E5M3 is a separate nine-bit arithmetic format specified in
`docs/signed-e5m3.md`.

```d
import icky.imprecise;

auto a = E3M2.from_float(1.0f);
auto b = E3M2.from_float(0.0625f);
auto rounded_sum = a + b;
float displayed = rounded_sum.to_float();

UE5M3 stored;
bool accepted = UE5M3.try_from_float(1.0f, stored);
// A failed construction leaves stored unchanged.
// stored + stored does not compile.

auto a = E5M3.from_float(1.0f);
auto b = E5M3.from_float(2.0f);
auto difference = a - b; // E5M3(-1), no Float16 arithmetic
```

Raw payload access is explicit: `from_code`, `code`, and `to_float`.
`E3M2.from_code` masks unused bits, matching the existing C contract.
Signed E5M3 uses logical layout `s eeeee mmm`, exponent bias 15, signed
zero/subnormals, infinity/NaN, and direct E5M3 rounding after `+`/`-`.
Multiplication/division are not E5M3 operators and require an explicit wider
arithmetic choice.
Its nine meaningful bits occupy a 16-bit scalar container; dense nine-bit
memory packing is a separate representation problem.

UE5M3 accepts binary32 inputs with no sign bit and exponent fields 112 through
143 inclusive. Zero, negatives, subnormals, out-of-range normals, infinities
and NaNs are rejected. Its code zero represents a positive bin midpoint,
**not numeric zero**; that also describes `UE5M3.init`.

## Packed memory access

`icky.packed` adds a scalar, byte-strided view and a typed `PackedValue!(S, A)`:
`S` names the stored representation and `A` names the arithmetic representation.
For UE5M3, `PackedValue!(UE5M3, Float16).sizeof == 1`; decoding constructs one
Float16 value at the point the caller requests arithmetic. Each successful
load reads one stored element. UE5M3 values beyond Float16's finite range widen
according to the existing Float16 overflow conversion. Stores encode one
arithmetic value and leave memory unchanged when the UE5M3 input falls outside
its defined domain.

```d
auto packed = PackedView!(UE5M3, Float16, 1, alias_group)(bytes, byteLength, 1);
PackedValue!(UE5M3, Float16) value;
if (packed.try_load(index, value)) {
    auto result = value.decode() * Float16.from_float(2.0f);
    packed.try_store(index, result);
}
```

The view carries its base, byte length, byte stride, caller-known alignment,
and optional alias-set label. The alias label does not assert disjointness.
Read/write effects and ordinary source ordering are recorded in
`PackedOperation!(S, A)`. Alignment records the caller-known guarantee; an
alias-set label is optional analysis information and does not assert
disjointness. Storage size, the decode/encode methods, and UE5M3's partial input
domain define the value semantics. Target properties such as ISA, SIMD width, cache descriptions,
prefetch distance, runner model, and fetch behavior do not enter the D API.

Inside DMD, `dmd.packedmemory.PackedMemoryOperation` carries the operation,
source/storage/arithmetic/destination types, storage size, base, bounds, index,
storage alignment, byte stride, known address alignment, alias set, conversion
policy, effect and order. The public packed calls reach this stage before
ordinary call lowering, and the scalar follower checks the complete request
before selecting the bounded scalar body. Its internal packed byte loads and
stores are lowered by `dmd.glue.e2ir.lowerPackedMemory` into ordinary
one-element accesses. The versioned `PackedMemoryTrace` receipt separates the
semantic request from follower execution, so the compiler-stage facts remain
visible without becoming hardware properties or being reconstructed from
lowered expressions.

This first surface performs scalar conservative lowering through ordinary D
pointer loads/stores and the existing `icky.imprecise` conversions. It does not
provide a target-specific follower yet. The view has no arithmetic array and
does not widen a range as a side effect of a load. The qualification receipt
source at `dmd/qualification/packed-memory/receipt.d` is compiled with DMD's
`-vasm` output and to an object whose x86-64 instructions are disassembled by
`objdump`; inspect those artifacts to see the code emitted by its exact DMD
build. No optimality claim
is made.

## Finite geometry

`Circle!n`, `Rotation!n`, `Reflection!n` and `Tangent!n` are separate categories.
The portable grid currently supports even `n` from 2 through 65536. The named
families are 96, 192, 240, 360 and 720.

- Circle points, rotations and reflections use canonical codes `0 .. n-1`.
- Tangents use the local interval `[-n/2, n/2)`, with the antipodal tie at `-n/2`.
- `from_ticks` is deliberately modular; `try_from_code` rejects a noncanonical
  external code and preserves its output on failure.
- Reflection with code `r` acts as `p -> r-p (mod n)`, matching Circle96.
- Third-sector access is available only on grids divisible by three.

```d
import icky.circle;

auto point = Circle96.from_ticks(95);
auto moved = rotate(Rotation96.from_ticks(2), point);
assert(moved.code() == 1);
assert(local_displacement(moved, point).ticks() == 2);
assert(displace(point, local_displacement(moved, point)).code() == 1);
// rotate(Rotation192.from_ticks(2), point) does not compile.
```

The 96/192/240 point, rotation and reflection types occupy one byte; 360/720
occupy two. Tangents use the corresponding signed byte or short. Circle96's
three sectors of 32 positions and flat/half-flat constants match the C source.
The larger grids use the same cyclic convention; this is not a claim to have
reproduced another repository's specialized packed codec for those grids.

## Qualification

The workflow `.github/workflows/dmd-representations.yml` checks the D source
with the host compiler, then builds the owned Icky DMD and executes both
unoptimized and optimized DMD output against the original C implementation.
It includes all 65536 binary16 payloads, every byte code for the smaller
formats, midpoint neighbours, randomized binary32 inputs, domain rejection,
requantization, invalid-operation type checks, the Circle96 C oracle and
finite-geometry laws for all five named grids. Packed-memory qualification
checks every UE5M3 byte through a stride-two view, decode/encode round trips,
F16 multiply followed by narrowing/store, bounds and domain failure, and
alignment/alias/effect facts.

The acceptance source uses `-betterC`, static storage and `@nogc`; the C oracle
is linked only into the test executable. The workflow result, not the presence
of the test files, establishes whether qualification passed.

## Full-family work that remains

Do not close the following simply because this first slice exists:

- #14: compiler representation selection and representation-specific lowering
  before target legalization; no premature flattening of semantic objects.
- #15: integrating the compact scalar operations with that backend seam and
  qualifying target-specific replacements.
- #16: integrating finite geometry with that seam, plus any separately defined
  representation layouts beyond this portable cyclic implementation.
- #17: ℍ (the dictated "hh"), Quaternion, UnitQuaternion, smallest-three,
  axis-angle/exponential representations and SO(n). General quaternions,
  unit quaternions and rotations must not be conflated.
- #18: S²/unit-pure-quaternion direction representations, CPⁿ and specialized
  CP² codecs, including their exact domain, reconstruction and error contracts.

In particular, S² direction coding is not S³ orientation coding, and CPⁿ is
not an arbitrary complex array. The earlier representation layouts and tests
must be recovered before claiming their ports. This slice does not substitute
new layouts or name-only declarations for those types. It does not establish
Android or physical-device acceptance.
