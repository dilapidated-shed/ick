# DMD geometric value representations

Continuation of the scalar/circle work in [dmd-representations.md](dmd-representations.md).
These are native D library value types with executable operations. They are not
new primitive compiler types, a representation-aware backend IR, or Android
acceptance. All implementation arithmetic is binary32; `HH` defaults to Float16
storage. No binary64 arithmetic or GC allocation is required.

## Hamilton algebra and unit values

`icky.geometry` exports:

- `Quaternion!Component`, with Component = Float16, float, E4M3, E5M2 or E3M2.
  `HH` and `hh` mean `Quaternion!Float16` (8 bytes); `HH32` is the explicit
  binary32 variant (16 bytes). Order is real, i, j, k. Addition, subtraction,
  negation, Hamilton product, conjugation and checked inverse are implemented.
- `UnitQuaternion`, a numerically normalized binary32 point on S3. Its default
  value is identity. Construction rejects zero, NaN and infinity. Normalization
  first divides by the largest absolute component so finite huge and subnormal
  inputs do not fail simply because their unscaled squared norm over/underflows.
- `ApproxUnitQuaternion!Component`, storing four rounded compact components.
  `radial_error()` measures the departure of the stored norm from one;
  `reconstruct()` explicitly renormalizes it. It is not silently substituted
  for an exactly unit mathematical quaternion.

A complete Hamilton operation evaluates its displayed coefficient expressions
in binary32, then requantizes each output coefficient once. This is an
**algebra-operation boundary**, not repeated compact rounding after every
internal multiply/add. Chained Hamilton operations do preserve intermediate
requantization. The component quantizers themselves retain their existing
scalar contract. E5M3 is not accepted as a quaternion component: the existing
unsigned, storage-only format is not given invented signed arithmetic.

`try_inverse` rejects zero, non-finite inputs and non-finite reconstructed
outputs. It still follows the chosen component format's rounding, underflow and
saturation rules; success does not certify a small inverse residual in a coarse
format. No caller-visible output is modified on failure.

A `UnitQuaternion` is an S3 point: q and -q are distinct there. `s3_distance`
measures their ordinary chord distance. `rotation_distance` minimizes that
chord distance over the two signs, identifying the same rotation action.
Neither method returns radians.

## Smallest-three storage

`SmallestThree!Component` omits the first component with maximal absolute value.
All four signs are reversed when that component is negative. The other three,
in increasing component-index order, are multiplied by sqrt(2) and encoded by
the existing scalar quantizers.

| Component | Bits per retained code | Total meaningful bits | Bytes |
|---|---:|---:|---:|
| Float16 | 16 | 50 | 7 |
| E4M3 | 8 | 26 | 4 |
| E5M2 | 8 | 26 | 4 |
| E3M2 | 6 | 20 | 3 |

Bits 0 and 1 hold the omitted index. The three codes follow, least-significant
bit first. Bit k is in byte k/8, bit k%8, independent of host endianness. Remaining
high bits must be zero. This is a **newly specified follower wire layout**; it is
not presented as an exact port of a separately deployed quaternion codec.

Reconstruction divides retained components by sqrt(2), reconstructs the omitted
positive component from sqrt(1 - retained squared norm), then normalizes in
binary32. Checked input rejects nonzero padding, non-finite codes, scaled
components outside [-1,1], and an impossible retained norm. It leaves the output
unchanged on failure. Raw decoding may accept multiple encodings of the same
rotation; byte equality is not rotation equivalence, and arbitrary valid raw
input is not promised to re-encode byte-for-byte. The encoder itself chooses a
deterministic omitted index and sign.

Identity has an all-zero payload. The equal-component point (1/2,1/2,1/2,1/2)
encodes in Float16 as bytes `a0 e6 a0 e6 a0 e6 00`.

### Error budget

On the scaled interval [-1,1], the maximum scalar rounding errors are
2^-12 for Float16, 2^-5 for E4M3, and 2^-4 for E5M2/E3M2. Call this error e.
The retained-coordinate error norm is at most sqrt(3/2)e in exact arithmetic.
The original retained norm is at most sqrt(3)/2. Even for e = 1/16, the segment
joining the original and rounded retained triples stays below radius 0.943.
The unit-sphere reconstruction map has derivative norm below 3 on that region;
using 4 gives a conservative real-arithmetic chord bound of 4 sqrt(3/2)e.

The implemented acceptance budget adds 0.000004 for binary32 arithmetic. This
allowance is an explicit tested numerical budget, not a formal proof about all
floating-point environments. Approximate bounds are 0.001201 for Float16,
0.153098 for E4M3 and 0.306191 for E5M2/E3M2. These loose worst-case budgets are
not claimed as measured typical errors or angular errors. The tests enforce the
actual `chord_error_bound` constant for 131072 deterministic samples per format,
plus axes, equal-component ties, golden bytes and malformed payloads.

## Directions and frame-typed rotations

`Direction!Frame` is a normalized point on S2. `S2` means `Direction!Unframed`.
Its pure-quaternion conversion has real component zero. Reverse conversion
rejects a nonzero real component, then explicitly normalizes the direction.
This is not an orientation on S3, and is not yet the existing octahedral codec.

`SpatialRotation!(Source, Destination)` carries directions between frames.
It retains a UnitQuaternion rather than reducing the semantic operation to a
matrix. Rotations are active and right-handed. `first.then(next)` applies first,
then next, so its quaternion is `next * first`. Inverse exchanges the frame
parameters. `SO3` is the unframed alias. Frame-mismatched application and
composition must fail type checking. `distance` compares rotation actions
modulo quaternion sign; component-wise operator `==` is deliberately disabled.

Checked unit/direction/packed types disable raw memberwise constructors. Their
valid default values and copying remain available. This protects the ordinary
API, not deliberately unsafe memory casts.

## Complex projective points

`icky.projective` exports `Complex32`, `CPn!n`, `CP1` and `CP2`.
`CPn!n` takes n+1 complex homogeneous coordinates, rejects the zero tuple and
non-finite inputs, normalizes length, and makes its largest coordinate positive
real. First index wins ties. The default point is [1:0:...:0].

`homogeneous_coordinates()` explicitly exposes the chosen representative;
it is not the meaning of equality of projective points. `distance` computes
`||z wedge w||` between normalized representatives. This is the chordal
projective distance (the sine of the usual Fubini-Study angle convention), not
an arbitrary distance between coordinate arrays. The wedge calculation avoids
subtracting nearly equal quantities in `sqrt(1 - |<z,w>|^2)`.

`same_point(other, tolerance)` is a numerical closeness test with an explicit,
finite nonnegative tolerance. Approximate closeness is not transitive, so it is
not installed as operator `==`. Coordinate-wise equality is disabled as well.
Construction must go through the checked homogeneous constructor; raw tuple
construction is disabled.

`try_chart(pivot, output)` divides by the selected coordinate and omits it. Zero
chart denominators, invalid indices and unrepresentable binary32 chart results
are rejected without changing output. Global nonzero complex rescaling and
phase changes are tested, including negative, imaginary, tiny and huge scales
whose resulting input coordinates remain representable. Finite precision still
loses information if an external rescaling itself overflows or underflows it.

## Qualification and scope

The `DMD value representations` workflow retains the scalar/Circle tests and
adds `geometry_acceptance.d`. It first compiles and executes with the host LDC,
then rebuilds the checked-out Icky DMD and compiles/executes both suites without
optimization and with `-O -inline`. Assertions remain enabled. The independent
C oracle applies a rotation matrix, whereas the D implementation uses Hamilton
products. Acceptance includes 4096 matrix-action comparisons, compact-codec
sweeps, invalid-input/no-mutation cases, type rejection, and CP0/CP1/CP2/CP4
rescaling and chart tests. Inspect the run for its exact tested commit; adding
this workflow or this document is not itself passing execution evidence.

Still required by issues #17/#18: general SO(n) and semantic plane rotations,
axis-angle/exponential-coordinate value representations, the existing 3-byte
S2 octahedral codec, specialized CP2 magnitude/phase packing, target-specific
lowering and physical Android acceptance. The representation-aware compiler
work tracked by #14 also remains open. None is replaced by an empty declaration
in this slice.
