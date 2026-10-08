# ICK large-integer multiplication benchmark lab

A small, portable **C11** harness for a candidate arbitrary-precision multiplier. It is not an implementation of OpenAI's 2026 algorithm. Its default schoolbook multiplier is a correctness and runtime baseline, **not** a practical competitor for very large operands. Independent exact multiplication is checked in `test_mulbench.py` with Python integers, and with Berkeley `bc` if installed.

## Reproduce locally

```sh
cc -O3 -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra mulbench.c -o mulbench
python3 test_mulbench.py
./mulbench --bench 8192 7 > baseline.csv
```

On ARM32 build with the matching Android NDK toolchain or qualified ICK compiler, then run the binary **on the physical device** for latency measurements. QEMU can test correctness and portability but does not predict MIRO A1 timing. AIX/POWER uses the same C11 limb interface, but its available clocks/compiler and host environment must be qualified independently. Do not compare cross-machine absolute timings without machine/compiler/memory metadata.

## Hook for ICK's algorithm

Implement this C ABI and link it into the same harness:

```c
int mul_candidate(const uint32_t *a, size_t na,
                  const uint32_t *b, size_t nb, uint32_t *out);
```

- Inputs: unsigned, *little-endian arrays of 32-bit limbs*, independent of host byte order; lengths in limbs.
- Output: the **entire** `na+nb`-limb exact product, initialized by the candidate, including high zero limbs.
- Candidate must preserve both inputs and return zero on success.
- Operand lengths are positive. The timed ABI excludes signed numbers; `--pipe` adds signed handling outside the multiplier.

```sh
cc -O3 -std=c11 -D_POSIX_C_SOURCE=200809L -DHAVE_CANDIDATE \
  mulbench.c candidate.example.c -o mulbench-candidate
./mulbench-candidate --bench 8192 7 > candidate.csv
python3 compare.py baseline.csv candidate.csv > paired.csv
```

`candidate.example.c` is only an adapter forwarding to the default schoolbook routine. Replace it with ICK's real component. Running the example does not demonstrate any speedup.

## Tests, workloads, and interpretation

`--pipe` consumes lines of two hexadecimal integers and writes their exact product in hexadecimal. The Python acceptance test sends the **same** deterministic corpus through schoolbook and candidate, across bit-width boundaries and signed, sparse, alternating, dense, random, square, and unbalanced cases. This checks the wrapper as well as the arithmetic, with an optional second oracle in `bc`.

`--bench [max_bits] [samples]` measures **hot, repeated, in-process multiplication calls**, for powers-of-two boundaries ±1 and the same broad pattern families. It performs calibration, takes multiple independent timed batches, and emits CSV with median and approximate p90 nanoseconds per call. The `pattern` codes are: `0` dense pseudorandom, `1` all-ones/carry-heavy, `2` alternating bits times all-ones, `3` sparse, `4` single top-bit. Output storage is reused, and the timed loop includes whatever allocation the candidate itself performs. A volatile sink prevents simple dead-code removal. A single repeated input is cache-hot and may benefit from operand-dependent fast paths. These numbers are **not** process-startup latency, realistic mixed-request throughput, cold-cache latency, peak-memory usage, or verified asymptotic complexity.

Treat three regimes separately in the full Sun/ICK work:

1. **Kernel latency:** this current `--bench` operation under warm caches; compare on one machine using the same compiler/flags and operand families.
2. **Request latency/throughput:** varied operands in a persistent process, batch sizes 1/8/64, end-to-end allocations and serialization; then separately measure one-process-per-call startup.
3. **Memory traffic and algorithm shape:** measure peak RSS/heap, allocations, cache/branch counters if permitted, frame moves, coefficient digit width, precision and truncation, address-field swaps, butterfly layers, and linear-network operations. Report instrumented counters separately from wall time.

For each run record Git commit, toolchain version and flags, OS and ABI, `uname -m`, machine model, actual ISA/softfp, frequency scaling/thermal state, thread count, and whether the run is native, virtualized, or emulated. Use medians and distributions; report the crossover where candidate becomes faster at each family and operand ratio. `compare.py` pairs matching case keys and reports a time ratio, but **does not** establish machine identity or statistical significance. For sub-microsecond calls, timing noise and loop overhead may dominate, so repeat across independent process runs and larger batches. Keep any additional memory/counter collection out of timed hot loops unless intentionally studying observer effects.

A no-claim performance report has columns: `architecture, compiler, algorithm, bits_a, bits_b, family, repetitions, samples, median_ns, p90_ns, speedup_to_schoolbook, peak_RSS, allocations, bytes_moved, notes`. When recording scaling, use observed logarithmic slopes only as finite-range measurements, not asymptotic proofs.

## Mathematical work versus implementation work

The 2026 OpenAI paper concerns a **fixed-tape Turing-machine** bit-complexity bound, not a promised speedup in C. Preserve separate accounting for tape moves, framed Gaussian-dyadic operations, simultaneous butterflies, address shuffles, and exact digit recovery. These counters may be more informative than absolute runtime for quite some time.

Input **texture** also matters: limb nonzero-density, Hamming weight, carry-chain depth, reciprocal/square/sparse/imbalanced shape, and arithmetically defined families (repunit and near powers of two, finite-field residues, resultant/discriminant coefficients, and number-theoretic sequences). Record data-generating *definitions*, not just a pile of big literals. Do not describe random field elements as elliptic-curve point coordinates without checking the curve equation.

The companion reading shelf lives in [ComputerScience books](https://github.com/walnut-burgundy/computer-science/tree/how-long%2Bhow-wide/books); [Seifert arithmetic topology](https://github.com/isomorphismes/seifert/tree/main/books); and [Fulton sources](https://github.com/walnut-burgundy/fulton/tree/main/sources).

## Concurrency and build constraints

The benchmark lab uses no external benchmark framework. The CI acceptance path can compile and execute it with native C and Python 3. Do not add unpinned GitHub Action dependencies or claim Android/POWER/AIX timing from a hosted x86-64 runner. Source-checks and emulators can catch mistakes, but the target device's measured results remain a separate gate. No automatic benchmark regression threshold should fail a build until variance and target allocation are characterized.
