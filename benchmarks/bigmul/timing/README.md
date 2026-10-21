# Standalone measurement engine

The C engine stores elapsed integer nanoseconds and repetitions. Calibration
caps total calls and accumulated measured time, and distinguishes reaching the
target from hitting a cap. Timers fail on zero/backward duration, failed clock
reads and invalid/overflowing seconds-to-nanoseconds conversion. A time cap is
checked after each batch; a blocking callback requires an outer process timeout.

The executable fixture records CLOCK_MONOTONIC resolution, process CPU time,
trial order, target/cap flags and full output limbs outside each timed batch.
CPU intervals include the wall timer reads. Its callback counter is intentional
fixture instrumentation, included in the reported interval; these measurements
qualify the engine and are not uninstrumented candidate speed results.

Arithmetic input arrives at runtime. The arithmetic object is compiled separately
with `-fno-lto`; optimized and LTO engine/driver builds retain that opaque boundary.
Generated disassembly, callback counts and complete outputs are checked. This is
stronger evidence than a single volatile sink but does not prove future providers
cannot cache a result; changing-input/provider tests belong to MB07/MB16.

Empty/copy controls have separate raw distributions; no overhead subtraction.
An even-sample median averages the middle two values. Batch quantiles use nearest
rank `ceil(probability * count)` with the first value at probability zero. These
are quantiles of batch averages, not per-request tail latency.

`python3 benchmarks/bigmul/timing/check_mb06.py` emits the complete raw run and
command receipt. Shared-harness integration waits for accepted MB02. This is the
host GCC control lane; qualified ICK and device lanes remain unqualified here.
