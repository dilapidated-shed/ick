# Compiler comparison receipt — 2026-10-06

Executed on Linux x86_64 using materialized ICK from base
`e3c2a40b4edafc4d9caca55d1f7c094e6aab9589` plus the fixture bytes bound in
[`fixtures.sha256`](fixtures.sha256). GCC reference:
`6294f1d9e7536e5ffcde09d1528c918d63abfef5`.
Compiler reports `GCC 17.0.0 20260813 (experimental)`.
Two fresh materializations compare equal. The full AArch64 backend and shared
A53 scheduler compare equal to the pinned reference. No compiler source changes.
NDK link/driver input: r29, `29.0.14206865`, Android API 21.

Both modes pass scalar, SIMD, branch/load and volume correctness under
QEMU 8.2.2 `-cpu cortex-a53`. All eight replay objects compare byte-for-byte.
Blank-renderer and bad-alignment negative controls fail as required. Android
ELF objects link to both Bionic oracle executables and shared libraries; every
native output passes ELF64/AArch64/DYN/zero-e_flags/16KiB PT_LOAD checks.
Both libraries export exactly the same four C symbols, with no undeclared
kernel helper symbols and no use of Android-reserved x18.

**Android runtime execution: NOT_RUN.**
**PHYSICAL PERFORMANCE COMPARISON: NOT_RUN.**
No QEMU timing was collected. No PowerVR backend or GPU performance claim.

## Size

`size`'s text column includes read-only constants and unwind data. Actual machine
code is reported separately as ELF `.text`. Sizes are bytes.

| Kernel | Generic `.text` | A53 `.text` | Generic `size` text | A53 `size` text |
| --- | ---: | ---: | ---: | ---: |
| scalar | 136 | 136 | 176 | 176 |
| vector | 212 | 212 | 252 | 252 |
| branch/load | 120 | 120 | 160 | 160 |
| volume | 392 | 400 | 504 | 536 |
| total | 860 | 868 | 1092 | 1124 |

Volume read-only constants increase 32 → 48 bytes, unwind data 80 → 88,
and code 392 → 400. This is a size increase, not evidence of improved speed.

## Assembly and optimization quality

Both modes use `-march=armv8-a`; feature macro sets match. `-mcpu=cortex-a53`
alone was separately accepted and enables CRC, so it was not used as the only
difference in this experiment. Both retain the existing defaults enabling the
835769 and 843419 A53 erratum controls. Target dumps report `-mabi=lp64`.
The GNU cross-driver reports glibc mode; only freestanding, header-free kernel
objects use it. Bionic headers, startup files and linkage come from NDK. This
is the established focused object/link boundary, not full Android driver proof.

The generic and A53 scheduler excerpts both name `cortex_a53_*` reservations.
GCC's generic entry **already selects the A53 DFA**. The genuine difference is
the selected costs/tuning model. Full emitted tuning-model dumps are retained.

- Scalar: assembly differs only in maximum function-alignment padding
  (`.p2align 4,,11` versus `4,,15`). At section offset zero this changes no
  bytes; object SHA-256 is identical.
- Branch/load: the same alignment-only change; object SHA-256 is identical.
  Data-dependent loads, `tbnz`, unsigned division/remainder lowering and
  arithmetic remain identical. No forced if-conversion or branch rewriting.
- Vector: same four-lane FP loop and scalar tail; A53 setup replaces generic
  duplicate `lsr` plus `lsl` with an `ubfiz` form and a shared shifted value.
  Object bytes differ, but code size remains 212 bytes.
- Volume: both modes vectorize **four independent pixels**, preserving each
  pixel's sequential 28-sample accumulation. The compiler reports one loop
  using 16-byte vectors in each mode. The report's missed inner-loop attempt
  says `outer-loop already vectorized`, not failure to use SIMD. Both emit
  `.4s` multiply/add/divide and an interleaved `st3` RGB store. No Float64
  instructions or promotion appear in the ray arithmetic.
- A53 replaces the pixel-coordinate scale using scalar `s7`/indexed
  `v7.s[0]` with a full vector constant loaded to `q5`, reshuffles register
  allocation and moves the row index constant's ADRP inside the row loop.
  It saves/restores d8–d15 using four STP/LDP pairs; generic saves d9–d15
  with three pairs plus scalar STR/LDR. The 64-byte stack frame remains
  unchanged and satisfies 16-byte alignment.

Static volume mnemonic counts retain **23 FMUL, 16 FADD, 3 FSUB, 1 FDIV** in
both objects (these counts include setup, not dynamic executions). A53 changes
ADRP 2 → 3, STP 3 → 4, LDP 3 → 4, STR 1 → 0; LDR stays at 3. Register-name
changes alone are not optimization. The save/restore operations are ABI
preservation, not loop-body spills. No load/store spills occur inside the ray
loop. The compiler hoists row and pixel transforms appropriately for their
dependencies, and materializes constants outside that inner loop.

Quality limits and next experiments:

- SIMD throughput already exists: four Float32 values per 128-bit vector.
- The redundant row-level ADRP and extra constant/register pressure in the
  tuned variant deserve physical comparison before changing GCC's costs.
- The sample-position conversion/scale repeats for each pixel batch. An
  application-level precomputed ray-coordinate array could trade work for
  memory traffic, but that is a separate fixture/source-layout experiment.
- FDIV remains a real vector divide. Reciprocal approximations would change
  semantics, so none was substituted.
- No FMA appears because the exact-rounding contract explicitly disables
  contraction. That is intentional, not a missed permitted transformation.
  A future `-ffp-contract=fast` experiment needs its own numerical oracle and
  physical comparison; no global unsafe-math change is justified here.
- These results do not predict current Pauli's Float64/transcendental hydrogen
  evaluator or driver-compiled GLES performance.

## Digests and artifacts

[`compiler-output.sha256`](compiler-output.sha256) binds all eight object hashes
and retained assemblies. [`native.sha256`](native.sha256) binds the locally built
native Android binaries and measurement procedure. These exact local native
hashes are a dated build receipt; CI artifacts independently bind their own
executed PR head. Toolchain startup/archive differences may change executable
bytes without changing kernel objects. Do not relabel one receipt as another.

Both mode oracle outputs:

```text
scalar  b7d5f40199e87d66
vector  09be5844547bfd15
branch  fbd5f15e
volume  433c7e24606b1dbd
```

The physical Grease procedure parsed with the verified Grease implementation
`5651cf97a1b5042f24f14112a7ade9a1518eb0bc` (native compatibility applet,
executable SHA-256 `7e31cd05b7a9d8fb2a4a9e003a7f3fcb0159138506d17f0fb28da8cbe22aa85c`).
Device-command preflight passes. The procedure itself was not executed on C67,
and no C67 Grease installation or delivery location is asserted.
