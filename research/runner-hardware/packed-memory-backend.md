# Packed-memory x86 backend research

Date: 2026-09-28. Base: `dmd-runner-memory-research` head
`62130a4ea44b00271b3c7fcaa83c613f7cd7cea4`.

This is architecture research, not optimized lowering or a benchmark.

## Evidence boundary

Corrected run [36399380725](https://github.com/dilapidated-shed/ick/actions/runs/36399380725)
retains three checksum-verified fingerprints. Sample 1 reports AMD EPYC 7763,
GCC `znver3`, AVX2/FMA/F16C and no AVX-512. Samples 2/3 report Intel Xeon
Platinum 8573C, GCC `sapphirerapids`, and AVX2/AVX-512 flags. All report four
logical CPUs/two cores, one guest NUMA node, 4-KiB base pages and 64-byte cache
lines. These are VM observations, not GitHub fleet guarantees.

GitHub documents a fresh standard public `ubuntu-24.04` x64 VM with 4 CPUs,
16 GiB RAM and 14 GiB SSD; it does not promise CPU model, physical channels,
cache ownership or bandwidth. AMD 56665 rev.3 supplies Zen-3-family cache,
translation, load/store and prefetch guidance. Intel Optimization Manual v50
supplies Intel cache/prefetch/streaming guidance. The failed AMD 70574 download
is unused. Intel 8573C remains a qualified guest name: `sapphirerapids` is a
compiler classification, not proof of physical SKU.

Architectural ISA facts remain separate. F16C converts IEEE binary16<->binary32
but supplies no binary16 arithmetic. AVX-512 FP16 supplies native IEEE
binary16 arithmetic. Intel documents that extension for Sapphire Rapids-family
processors. Any later run must gate it on that run's CPUID/OS-visible features,
not the model string.

## Exact E5M3 semantic consequence

Current ICK/Icky D unsigned Ootomo-Naruse E5M3 decodes exactly as:

```
binary32_bits = (code << 20) + 0x38080000
```

It is not OCP E5M2/E4M3. Generic FP8 conversion is invalid unless proved
equivalent to this midpoint reconstruction.

For the repository's current `Float16` conversion, exhaustive algebra gives:

```
code 0..7:     half_bits = (code << 6) + 0x0220
code 8..247:   half_bits = (code << 7) + 0x0040
code 248..255: half_bits = 0x7c00
```

Thus E5M3->binary16 needs no intrinsic F32 intermediate. Codes 0..7 become
binary16 subnormals; 8..247 are exactly representable; 248..255 overflow to
+infinity. Calling this a "widen" is convenient but not information-preserving
for the top eight codes. An optimized implementation must exhaustively verify
all 256 codes against the semantic codec.

The intended compiler path stays: packed load -> decode/widen near use ->
arithmetic representation -> optional encode -> packed store. Array-sized
widened temporaries remain forbidden.

## Candidate decode/data paths

**Scalar reference.** `load8 -> zext32 -> shl 20 -> add 0x38080000 -> bitcast
f32`. This is the correctness baseline on ordinary x86-64. If Float16
arithmetic semantics require requantization, apply it at the semantic boundary.

**Scalar direct-half.** Construct the three ranges above with branches/cmov or
branchless masks. Zen 3 can then use F16C to reach FP32 arithmetic. A target
with AVX-512 FP16 can feed native FP16 arithmetic.

**Vector integer reconstruction to FP32.** Load packed bytes, widen byte lanes
to dwords, shift 20, add the base, reinterpret as FP32, then consume promptly.
AVX2 performs expansion in pieces; AVX-512 can use wider conversion/masking.
One packed byte becoming four register bytes is central to register pressure.

**Vector direct-half.** Load bytes, widen to words, classify codes <8 and
>=248, then form half payloads with shifts/adds plus blends/masks. Register
expansion is 1:2. AVX2/F16C then converts half groups to FP32 for arithmetic;
AVX-512-FP16 targets can remain FP16 where semantics permit.

**Lookup control.** A complete half table is 512 B; an F32 table is 1 KiB.
Scalar indexed loads are plausible. AVX2 arbitrary 256-entry lookup needs
decomposition; AVX-512 has stronger gather/permute machinery but still pays
index/table traffic. This is a measurement control, never representation
semantics.

No acquired evidence establishes a direct instruction for this E5M3 codec.

## Widths and "wide fetching"

Keep five widths separate: storage width (1 B/coordinate), memory-load width,
packed-register width, coordinates decoded together, and arithmetic width.
A 64-byte cache line contains 64 packed coordinates but does not require one
64-byte instruction. A 32-byte packed load may fan out into two 256-bit half
groups or four 256-bit float groups.

Useful experimental boundaries are scalar/word groups, 128-bit, 256-bit and
512-bit where legal. "Wide fetching" means sustaining useful packed-byte flow
with enough independent work to cover latency; it does not mean selecting a
DRAM channel or making an individual value wide.

## Memory hierarchy classification

**Generated instructions can directly select:** load/store forms and widths,
scalar/SIMD forms, software-prefetch instructions/hints, non-temporal stores
when legal, and target ISA variants.

**Generated code can influence indirectly:** loop order, stride, unrolling,
independent pointer streams, prefetch distance, alignment, temporal reuse,
register blocking and widened-value lifetime. These affect cache-line use,
hardware prefetch, TLB pressure, miss concurrency and load/store pressure.

**Program/compiler surface can expose:** packed element layout/size, stride,
alignment guarantees, alias information, read/write effects, ordinary access
shape, and whether encode/store is semantically required.

**Target/backend facts:** ISA features, legal/preferred vector widths, ABI and
cost-model data. Cache-line size may guide tuning but is not value semantics.

**Measurement/allocation facts:** effective cache capacity, sustained
bandwidth, effective memory-level parallelism, useful prefetch distance,
vector throughput/downclock effects, working-set TLB behavior, host contention
and host placement.

Physical DRAM channel selection, "load into L2", DIMM geometry and host NUMA
placement stay absent from Icky D/IR. Ordinary x86 loads cannot request those.

## Fetching, streams and widened lifetime

Future experiments should vary packed load/group width; unroll count; one
versus several independent pointer streams; no software prefetch versus a few
distances; contiguous versus selected fixed strides; interleaved versus
separate arrays only when semantics admit both; aligned versus offset starts;
working-set size; and arithmetic intensity.

Several apparent knobs overlap. Adjacent narrow loads can cause the same
cache-line traffic as one wide load. Unrolling and independent streams both
increase independent in-flight work, although streams change addresses.
Prefetch distance only has meaning relative to bytes/iteration and concurrency.

Default short-lived schedule:

```
load packed group -> decode -> arithmetic -> consume/reduce/store
                  -> discard widened lanes
```

Keeping several decoded groups live may hide latency and expose ILP, but raises
register pressure. FP32 expands register footprint 4x from E5M3; FP16 expands
it 2x. Widened spills can quickly erase packed-memory traffic savings. No
documentation result selects the best live-group count.

## Bounded backend strategies

| ID | packed load / decode | arithmetic | hardware | expected advantage | expected bottleneck / assembly receipt |
|---|---|---|---|---|---|
| S0 | byte; scalar bit reconstruction | scalar FP32 + semantic requantization | baseline x86-64 | correctness oracle | instruction overhead; receipt exact shift/add and no widened array |
| S1 | 16/32 B; AVX2 byte->dword reconstruction | AVX FP32 | AVX2; both observed families | common exact vector path | 1:4 expansion/unpack pressure; receipt vector zext/unpack, shift/add, `v*ps` |
| S2 | 16/32 B; byte->word direct-half piecewise mapping | F16C -> FP32 op -> F16 boundary | AVX2+F16C; observed AMD supports both | compact decoded staging | classification + conversions; receipt piecewise half mapping and `vcvtph2ps/vcvtps2ph`, no native FP16 claim |
| S3 | 32/64-B chunking; AVX-512 integer reconstruction | AVX-512 FP32 | required AVX-512 subsets/OS state | wider lanes/masks | expansion/register pressure; receipt EVEX decode + FP32 ops |
| S4 | 32/64-B chunking; AVX-512 direct-half | native FP16 | AVX512-FP16 plus integer subsets | 1-B storage, 2-B arithmetic lanes | decode + FP16 execution/wide-vector effects; receipt piecewise mapping followed by intended `v*ph` ops |
| S5 | scalar/vector indexed 512-B half or 1-KiB float table | target-dependent | baseline scalar; vector target-dependent | removes arithmetic codec reconstruction | table/index dependency; receipt actual table loads/gathers |

Load width, unroll count, prefetch distance and live-group count are parameters
inside these families, not additional strategies.

## Later experiment design

Every result must preserve exact runner fingerprint, compiler revision/flags,
generated assembly, image/kernel receipt, layout/working set and raw samples.
Hosted-runner noise requires repeated samples and preferably repeated
allocations; report distributions/medians and dispersion rather than one time.

1. **Conversion-bound:** source hot in L1; decode plus tiny consume. Normalize
   by coordinates and packed input bytes. This distinguishes reconstruction,
   F16C, native FP16 and table costs.
2. **L1-resident arithmetic:** fixed small working set and fixed operations per
   coordinate. Sweep a few live-group counts to expose ILP versus spills.
3. **Cache sweep:** geometrically increase working set across reported cache
   scales. Treat knees as observed behavior, not proof of exclusive capacity.
4. **Memory streaming:** working set well beyond guest cache descriptors.
   Compare E5M3 with semantically matched wider stored representations.
   Report coordinates/s, source/destination bytes and useful GiB/s.
5. **Bandwidth saved versus widening cost:** run matched kernels with identical
   arithmetic/results while changing only storage/decode path.
6. **Access pattern:** contiguous plus a bounded set of fixed strides chosen to
   cross cache-line/page boundaries; only then test multiple independent
   streams and software prefetch.

Separate warm-up from timed repetitions. Randomize strategy order within a run
where practical. Pin/report CPU affinity if permitted, record migration if not,
and retain outliers rather than silently deleting them. Performance counters
are optional evidence only if the VM exposes trustworthy access; wall-clock
and assembly receipts remain mandatory.

Dependent measurements: ns/cycles when available per coordinate, coordinates/s,
useful packed input bytes/s, total explicit bytes/coordinate, and output/checksum
for semantic equivalence. For conversion-bound tests also report decoded
coordinates/instruction group; for streaming tests report working set and
stride in bytes and cache lines.

### Assembly receipts

Each experiment stores disassembly and checks for the intended family:
S0 scalar byte reconstruction; S1/S3 vector byte expansion + shift/add + FP32;
S2 F16C around direct-half construction; S4 actual FP16 arithmetic; S5 table
addressing. All strategies reject array-sized widened stores/spills as an
implementation failure for this use case. Record unexpected calls, scalarized
loops, spills and target-feature fallback instead of assigning timings to the
intended strategy.

## Compiler-surface implications

| fact | classification |
|---|---|
| packed load/decode/arithmetic/encode/store ordering | already expressible semantic information |
| E5M3 8-bit layout, valid codes, exact midpoint reconstruction, Float16 overflow behavior | representation metadata |
| stride, alignment, aliasing, read/write effects | memory metadata |
| likely streaming/no reuse, prefetch desirability, preferred grouping if ever exposed | optional optimization hint only |
| CPUID features, legal vector widths, ABI, cost model, observed cache-line size | target description |
| scalar vs AVX2 vs AVX-512, F32 vs native FP16 lowering, load grouping, unroll, prefetch distance, live groups, table use | backend-internal decision |
| bandwidth, effective cache capacity, MLP, useful prefetch distance, wide-vector behavior, VM contention | measurement-only fact |
| physical DRAM channels/cache ownership/host NUMA | measurement/host fact; absent from language and IR |

No genuinely missing language primitive follows from this analysis. The
assumed representation-aware surface plus representation metadata and ordinary
memory facts can express every semantic requirement needed by the experiment
families. The backend can choose load width, vector width, decode sequence,
schedule and prefetch itself.

One point must be explicit in representation metadata or the existing decode
definition: E5M3->Float16 is a conversion with the specified top-eight-code
overflow, not an information-preserving widening. If the intended compiler
surface already identifies the source codec, destination representation and
conversion rule, no new field is needed. Only if it represents "widen" as an
opaque width increase without recoverable conversion semantics would that be a
real gap.

## Unresolved measurement questions

Documentation cannot decide whether direct-half beats direct-F32
reconstruction, whether AVX-512 width helps this VM, how many live groups or
streams are useful, whether software prefetch helps, where effective cache
knees lie, or whether one-byte storage saves enough bandwidth to repay decode
cost. It also cannot establish runner memory-channel bandwidth.

## Sun handoff

The later Sun pass should reconcile this document with the landed
representation-aware compiler surface. It should verify that conversion
semantics (especially E5M3 codes 248..255), representation metadata and
stride/alignment/alias/effect facts survive to the backend; map S0-S5 onto the
actual backend seam; and then choose the smallest implementation/probe sequence
that can produce the assembly and timing receipts above. It should not promote
EPYC/Xeon cache/channel facts into language semantics or select a winning
strategy before measurement.
