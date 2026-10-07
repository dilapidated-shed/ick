# Android arm64-v8a / Cortex-A53 qualification

This is CPU compiler qualification, related to
[ICK issue #65, “Qualify Cortex-A53 tuning for MIRO C67 after the ABI receipt”](https://github.com/dilapidated-shed/ick/issues/65).
It adds no backend and no `miro-c67` ABI. Physical performance remains
**PHYSICAL PERFORMANCE COMPARISON: NOT_RUN** until the phone returns a receipt.

## Source and selection

Base ICK: `e3c2a40b4edafc4d9caca55d1f7c094e6aab9589`.
GCC reference: `6294f1d9e7536e5ffcde09d1528c918d63abfef5`, from `ick/SOURCE.lock`.
Materialization preserves the entire `gcc/config/aarch64/` directory and
`gcc/config/arm/cortex-a53.md` byte-for-byte. None is an ICK overlay or prune
path. ICK's shared optimizer overlays still apply; this gate exercises their
ordinary C path. The Android workflow compares two materializations and checks
the backend against the reference before running this qualification.

The pinned GCC already implements:

| Command-line form | Architecture | Tuning / scheduler |
| --- | --- | --- |
| `-march=armv8-a` | Armv8-A, FP and Advanced SIMD, no CRC requirement | Default tuning unless separately selected |
| `-mcpu=cortex-a53` | Armv8-A **plus CRC** | A53 costs and A53 pipeline |
| `-mtune=cortex-a53` | Does not select architecture extensions | A53 costs and A53 pipeline |
| `-march=armv8-a -mtune=generic` | Baseline Armv8-A | Explicit generic costs; GCC already maps its DFA to A53 |
| `-march=armv8-a -mtune=cortex-a53` | Same baseline Armv8-A | Explicit A53 costs/scheduler |

These are joined options (`-march=…`, `-mcpu=…`, `-mtune=…`), not split
`-mtune cortex-a53` arguments. `aarch64.opt` declares them `ToLower`, joined,
negative-rejecting options. Architecture and CPU extension modifiers use GCC's
existing parser; no new ICK spelling is added. The gate retains accepted target
options and feature macros, including the CRC distinction of the standalone
`-mcpu=cortex-a53` form. Explicit `-march` overrides the architecture selected
by `-mcpu`; explicit `-mtune` overrides its tuning.

`aarch64-cores.def` maps Cortex-A53 to V8A + CRC and `cortexa53_tunings`.
`tuning_models/cortexa53.h` supplies A53 arithmetic costs, GP↔FP move cost 5
(versus memory cost 4), two-issue rate, ADRP/ADD and ADRP/LDR fusion preferences,
and weak automatic prefetch behavior. Its vector costs remain the generic
vector cost table; A53 tuning does not invent a different SIMD ISA.
`aarch64.md` includes `../arm/cortex-a53.md`, whose DFA models two issue slots,
load/store address-generation restrictions, branches, integer divide/multiply,
and FP/SIMD pipeline reservations. `tuning_models/generic.h` instead uses
Cortex-A57 extra arithmetic costs and generic register/vector/branch costs.
An important pinned-source detail: the `generic`, `generic-armv8-a` and
`generic-armv9-a` entries also name `cortexa53` as their scheduling core.
`aarch64_override_options_internal` selects that `sched_core` independently
of the cost table. Consequently **both compared modes use the A53 DFA**;
this experiment changes the generic versus A53 cost/tuning tables, not the
underlying pipeline automaton. The retained scheduling dumps establish that
fact directly. Inventing a separate generic scheduler would change the baseline.

The exact common command is:

```text
ICK -std=c11 -O3 -fPIC -ffixed-x18 -march=armv8-a
    -ffp-contract=off -fno-fast-math -ffreestanding -nostdinc
    -Iqualification/cortex-a53 -mtune=generic -c KERNEL.c -o KERNEL.o
```

The tuned command changes **only** `-mtune=generic` to `-mtune=cortex-a53`.
`scalar.c` alone adds `-fno-tree-vectorize` to expose scalar scheduling. All
other fixtures keep normal vectorization enabled. Contraction is disabled
locally for exact separate-operation rounding, not globally in the compiler.
No fast-math, reciprocal approximations, relaxed NaNs or flush-to-zero modes
become default. AArch64 Advanced SIMD is ordinary architecture functionality;
the four-lane Float32 loop needs no ARMv7-style relaxed-math permission.

This uses the existing focused ICK GNU cross-driver/object → NDK r29/API 21
link lane, not a newly complete Android ICK sysroot driver. ICK builds **all**
workload objects. NDK compiles only the Bionic oracle/measurement drivers and
links the objects. The public contract remains AAPCS64, LP64, ELF64/EM_AARCH64,
PIC, reserved x18, the same four exported C signatures, and 16 KiB PT_LOAD
alignment. Target macros and shared-library exports are compared. AArch64
does not use ARM32 `.ARM.attributes` CPU tags to communicate A53 scheduling;
`readelf -hAn` and Android notes/properties are retained instead. ELF e_flags
must remain zero. Build-ID differences are artifact identities, not ABI changes.

## Kernels and oracles

- `scalar.c`: four independent Float32 recurrences and exact final values.
- `vector.c`: independent array outputs, legal `restrict` use, four Float32
  values per NEON register, no reassociated reduction. The oracle also tests
  signed zero, infinity, NaN, subnormal rounding and a non-vector tail.
- `branch.c`: bounded loads, data-dependent branches and defined unsigned
  wrapping arithmetic; zero count performs no loads or divisions.
- `volume.c`: nested 128×128 image / 28 ray loops, fixed-coefficient coordinate
  rotation, polynomial density and three-channel Float32 accumulation.

Pauli reference:
[isomorphismes/pauli PR #23, “Drive Android orbital rendering with checked hydrogen states”](https://github.com/isomorphismes/pauli/pull/23),
source `5f9f8a0fc08e4d4dd978298f47112af0ad02f196`, especially
`android/native/pauli_volume_image.c` and `pauli_orbital.c`.
The current Pauli spatial/ray and color path uses Float32 but the checked
hydrogen evaluator uses Float64 and transcendental functions. This small
fixture deliberately models only the requested Float32 CPU shape. It does
not replace, reproduce or validate those hydrogen formulas. It evaluates all
458,752 sample positions; Pauli's sphere clipping makes that an upper bound
for the actual application. It does not model GLES presentation.

The scalar oracle uses a different stream organization. The pointwise oracle
uses exact dyadic inputs and double intermediates. The load oracle uses
division/modulo formulations independently of the kernel's bit operators.
Volume FNV-1a digest `433c7e24606b1dbd` was frozen after a host GCC 13 `-O0
-ffp-contract=off` reference evaluation of all 49,152 output values; an `-O2`
host replay agrees. The digest serializes each binary32 word in little-endian
byte order, not native memory order. This is a regression oracle, not an
independent hydrogen-physics oracle. Both ICK variants must produce exactly
the same required oracle output under `qemu-aarch64 -cpu cortex-a53`.
QEMU establishes Linux correctness, never Android execution or performance.

`make -f qualification/cortex-a53/Makefile all regression` creates assembly,
objects and replay objects, size output, instruction-mnemonic counts, vector
reports, post-register-allocation scheduling dumps, ELF metadata, symbols,
fixture hashes, exact source commit, compiler configuration, Android executables
and shared libraries. Each replay object must match its original bytes.
Negative controls require a blank volume renderer to exit 16 and a 4 KiB
ELF alignment fixture to fail with the expected diagnostic. The workflow runs
unfiltered on the exact PR head alongside all four existing Android ABI lanes.

## Physical measurement

The CI artifact contains `c67-native-benchmark.tar.gz`, plus `native.sha256`.
These are native Bionic ELF files, not APKs; APK signing does not apply. Keep
the artifact's exact workflow/head and hashes with the receipt. Extract on the
build/download host, preserving executable bits, then deliver the complete
folder to a verified **executable private C67 directory** using the current
Cat Food device records. Do not execute out of Android shared Downloads.
No compiler or build dependencies are needed on the phone.

Let the device cool, disconnect charging, close other active workloads and
record those conditions. `benchmark` finds its sibling libraries through
`/proc/self/exe`, verifies exact `Miro C67` identity, and prints observed Android
properties, kernel identity and page size. It checks the reference image before
timing and compares both variants after every pair. The same driver warms up
each mode three times, then measures 31 pairs × eight frames, alternating AB/BA
order. Retain all 62 durations; compare medians and spread (ideally repeat the
whole session). The test does not pin core/frequency or control thermals, so
heterogeneous frequency policies, throttling and background work remain noise
sources. A single timing or emulator timing cannot establish a speedup.

The pasteable invocation, after delivery, is the **verified absolute native
benchmark path** with no arguments. No shell state or current directory is
required. `measure.grease` additionally verifies SHA-256, runs both Android
oracles, writes their output and the timing TSV, and checks identity before
execution. Invoke it through the target's verified Grease entrypoint; do not
run it through Bash. The C67 Grease runtime and physical procedure are
**NOT_RUN** in this environment; host Grease parsing is narrower evidence.
No delivery path or runtime installation is guessed.

Until actual C67 receipts arrive: **PHYSICAL PERFORMANCE COMPARISON: NOT_RUN**.
Issue #65 remains open for physical comparison; the narrow Pauli installation
report does not close ai-ci #196. See the [C67 target map](../../docs/miro-c67-target-map.md)
for the exact APK evidence and the separate GE8320 shader-compiler boundary.

## Measured compiler result

See [retained evidence and analysis](evidence/README.md). Both modes pass the
same deterministic oracle. Scalar and branch objects are byte-identical. The
vector loop's setup changes; the volume loop uses different constant forms,
register allocation, scheduling and save/restore sequences. Both volume loops
already process four ordinary Float32 pixels per SIMD register. No Float64
promotion or unsafe math is needed. Physical speed remains unknown.
