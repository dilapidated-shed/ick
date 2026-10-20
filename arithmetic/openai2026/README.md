# Exact arithmetic component

MUL-1 implements checked sign/magnitude 32-bit limbs, exact dyadics,
rectangular Gaussian values and the paper's actual eight scalar schedule
steps for h=6. Forward, inverse and three-call signed swap preserve arbitrary
auxiliary values. This is a scalar component, not a whole multiplication routine.

Initialization takes a fresh record and leaves canonical zero on failure.
Clear releases the record's original, independently owned initialized storage.
Storage belongs to each initialized record. Distinct record buffers must not
overlap; the same record may be both input and output. Checked arithmetic,
copy, network and serialization failures leave valid destinations unchanged.
Capacity includes intermediate alignment and additions. Metadata and initialized
buffers must remain valid for the duration of a call. Calls do not support
concurrent mutation. Serialization is exact big-endian two's complement at the
requested scale; coarse rounding is an explicit separate operation and truncates
magnitude toward zero. Byte output must not overlap limb storage.

The independent Idriç Integer oracle produces 99,294 complete endpoint records:
67 inputs × three routes × 247 Gaussian fields × two channels. Inputs include
the original 12 deterministic and 20 basis STAR model cases, additional signed
Gaussian cases, nonzero scratch, zero sources and large limbs. It also exports
126,464 internal records for all eight actual schedule steps of the original
32 STAR cases; the component's independent observer emits matching snapshots.
The complete contract therefore has 225,758 records. The whole-product
TSV is verified as the immutable shared input pin. Scalar execution does not
claim to execute those whole products.

The required `check` and `mutants` Make targets take absolute `ICK_CC`,
`ORACLE_IDRIC` and `CORPUS` paths. The oracle compiler must report the pinned
2734ac5a8 revision and use Chez. `check` retains actual output, candidate and gate
statuses, dynamic symbols, dependencies, executable disassembly and hashes.
`mutants` invokes the same outer runner on wrong-side-sign, omitted-undo,
dropped-carry, zero and oracle-bypass executables. Each failed child or comparison
must survive the outer runner with a nonzero status. Oracle delegation fails
the import gate even when serialized values match.

The component intake preserves advanced main c61e448251744a2f40ad743ebef1a027bdcd2f9d.
The retained runtime source 143e29580c2644ea0f345fe609fa5673d036865d was built
separately through its existing materializer with pinned GCC. Its fresh native
compiler, libgcc, libatomic and all 21 native runtime tests passed; no new runtime
repair is included. Bootstrap host gcc/g++, oracle Scheme and maintained ICK
compilation are separate stages. See `dependencies.lock` and generated receipts.

MUL-4 adds precision-certified roots and Gaussian exponentials and the ordered
resampling maps A=S/2 and B0=D' J' C. Its admitted domain is p=101..256,
2<=s<t<=64, coprime lengths, alpha>=2, alpha^2<p and
(t-s)alpha^4>ps. A plan owns its explicitly bounded coefficient storage; caller
arrays own initialized Gaussian records and must be disjoint. Capacity,
aliasing, disk, grid and parameter failures preserve every destination.

All trusted constants and functions use directed dyadic bounds, checked
32-bit-limb products, finite series and explicit remainders. The private work
precision is p+64 and storage is limited to 1024 bits. C uses upward nearest
ties and an increasing coordinate scan. J' executes the prescribed alternating
Neumann terms; D' includes its original scaling. Both ordered maps have error
strictly below p^2 2^-p. CERTIFICATES.md gives the scalar, line, tensor and
amplified identity obligations and the exact pinned author-PDF hash.

The independent Idriç reference uses different series at p+128 bits, directly
sums wider Gaussian kernels and encloses a longer inverse. The 8,090-record
contract checks scalar intervals, all line basis directions, signed dense and
half-grid inputs, ordered nearest indices, the retained Ps/Pt Fourier identity,
and two tensor lines on a 2x18x19x3 box. All unused padding stays zero and every
tagged prefix/suffix field retains its physical position. A normalized quadratic
DFT supplies verification only; A and B0 do not call a transform.

`check-resampling` and `mutants-resampling` take the same absolute compiler and
corpus arguments as `check`. Evidence under `build/resampling` includes actual
stdout/stderr, interval/reference hashes, ELF/dependency inspection, preparation
allocations, CPU time for constant generation, outer wall time and Linux peak
RSS. Counters are labeled RAM. The five prescribed defects and an additional
byte-matching oracle bypass must fail with nonzero outer statuses. The bypass
is rejected by its extra process import even when every value matches.

These bounded correctness profiles use conventional checked limb products.
They do not establish the cited running-time theorem or a whole multiplier.
Dependent recovery must account for the explicit 2^(2alpha^2) amplification
and every subsequent scale before claiming a strict half-unit error bound.
