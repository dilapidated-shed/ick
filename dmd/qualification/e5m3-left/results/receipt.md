# Host evidence receipt, 2026-10-07 UTC

Source base: `45a65d8b8c8928843b1bdaa1e737ce8b5ae814e0`, IDK branch.
Consumer build toolchain: `ick`; selected compiler is the owned IDK DMD
source at this base. No production compiler source was changed by F03.

Host: disposable Ubuntu 24.04.3 x86-64 container, AMD EPYC 9V74.
Observed cache: L2 1024 KiB, L3 32768 KiB. No ARM device was accessed.

Compiler SHA-256:
`588f84bda38babc9c11062f2e79c52a60f6e932d48151f8c7aef954ae5c9ab16`.

The compiler was bootstrapped using Ubuntu LDC 1.36.0 (package revision
`1:1.36.0-2ubuntu2`), with the repository's existing `build.d` entrypoint.
Packages were extracted into the disposable workspace; no system installation
or user-device installation succeeded or was needed. The bootstrap linker is
the host linker; this is compiler-bootstrap provenance, not a consumer fallback.

Source SHA-256:

| Source | SHA-256 |
|---|---|
| `dmd/library/icky/experimental/e5m3_left.d` | `5f480e01868e96f8821c190e69d79264b91f204b2f665b2336fae483816d9aaf` |
| `dmd/qualification/e5m3-left/acceptance.d` | `93cedf1cccfdfb28eeae56caa62c321addddccbe1823c631812078e342b10299` |
| `dmd/qualification/e5m3-left/benchmark.d` | `5b36fa67b877cfaa9ced5814354a0b18a0779840b9b0113cba01dab04749fcf0` |

Executable SHA-256:

| Artifact | SHA-256 |
|---|---|
| debug acceptance | `e9ed596ddcb7de934033307efcd5db76dfe681a4a462cafa5d05c0e2f9553b9e` |
| optimized acceptance | `ff6595bad7a6948d138322e075adbbf3abde410f41e20657af44ae12d038775f` |
| optimized benchmark | `38f889456ffbb4e97fe3a41ececd8c9524b72cb3a580954072b3105e49574362` |

Both acceptance executables exited 0 and reported:

```text
PASS: all 65536 FP16 inputs and all 65536 storage validation inputs
PASS: all 512 values; all 262144 pairs for add/sub/explicit-half-multiply and six comparisons
PASS: 1488 binary32 rounding-boundary neighbours and ties; NaN normalization stays specified
```

Benchmark exited 0. All 282 data rows were present; cross-layout checksums
agreed for every workload, size and sample. Seven samples per layout for each
small tier; three per layout for the streaming tier. Kernel numbering is
defined in the design note. Benchmark ELF: text 45211 bytes, data 632, bss 144;
the harness includes both layouts and shared code. Per-kernel body sizes and
static instruction counts are recorded separately, and exclude called helpers.

## Invocation recipe

Working directory: repository root. This is an argument recipe, not a mobile
installation procedure. Resolve `IDK_DMD` to the rebuilt compiler and
`RUNTIME_IMPORT` to the observed host's declaration-import directory before
using the recipe; neither is a generic PATH assumption.

Common arguments, in order:

```text
-betterC
-I<RUNTIME_IMPORT>
-Idmd/library
dmd/library/icky/imprecise.d
dmd/library/icky/experimental/e5m3_left.d
```

Debug qualification appends `dmd/qualification/e5m3-left/acceptance.d` and an
explicit `-of=<debug-output>`; execute that output and require exit 0.
Optimized qualification adds `-O -inline`, uses the same acceptance source,
and a separate output. Benchmark uses `-O -inline`, substitutes
`dmd/qualification/e5m3-left/benchmark.d`, and captures its stdout to TSV.
Do not use `-release`: these qualifications require their assertions.

Actual executable on this host:
`/workspace/scratch/82d63b2a1446/ick-idk/dmd/generated/linux/release/64/dmd`.
Actual declaration path:
`/workspace/scratch/82d63b2a1446/bootstrap/usr/lib/ldc/x86_64-linux-gnu/include/d`.
The compiler required the extracted LDC shared-library directory in
`LD_LIBRARY_PATH` because of its bootstrap link; consumer executables did not.
Bootstrap invocation from `dmd/compiler/src` was `ldmd2 -run ./build.d dmd`
with `HOST_DMD` set to the observed extracted `ldmd2` absolute path.

## Target boundary

ARM admission probe added `-mtriple=armv7a-linux-androideabi21 -betterC -c`
to the owned compiler with the experimental source. Exit 1:

```text
Error: unrecognized switch '-mtriple=armv7a-linux-androideabi21'
```

ARM/Thumb emission, assembly, target ELF size, QEMU execution, physical
execution and physical timing: NOT_RUN. The `.S` comparison is handwritten
source, not generated or assembled evidence. No CI run for this new
qualification is claimed. Default-layout adoption is blocked on those
target-specific results and a favorable overall cost comparison.
