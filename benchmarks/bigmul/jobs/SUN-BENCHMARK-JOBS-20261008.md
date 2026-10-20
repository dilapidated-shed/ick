# SUN multiplication benchmark and mathematical-workload assignments

Prepared 2026-10-08. **28 new assignments; no child execution is dispatched by this document.** These accompany, rather than replace, STAR MUL-0's eight existing assignments: SUN MUL-1 through MUL-6 and SUN ARM-1 through ARM-2. The objective is to have executable acceptance, useful timing modes and reproducible evidence ready when the actual ICK multiplication implementation becomes available. A mathematical reading investigation is not on the critical path to the first benchmark.

## Common execution contract — include with every separately pasted assignment

Receiver: **SUN, implementation and execution**, with a substantial reasoning budget. Produce working code, run the scoped checks, and return artifacts; do not stop at another plan. A job marked WAIT may prepare an isolated implementation but cannot claim integrated acceptance until its named predecessors have accepted immutable receipts. A missing external machine blocks only that machine's execution, not local preparation.

### Inspected starting points

- **B — benchmark owner:** `dilapidated-shed/ick`, retained PR #82, branch `bench/bigmul-harness-20261008`, inspected code commit `44ca65637acc6410a649502a139560412c7e108c`. The default-branch ancestor is `main@15f1f842f5da25f4e5a66fbbb18d24b99a141a8f`. Reuse `benchmarks/bigmul/{mulbench.c,candidate.example.c,test_mulbench.py,compare.py,network_shape.py,README.md}` and `.github/workflows/bigmul-benchmark.yml`.
- **S — STAR handoff:** `walnut-burgundy/computer-science@32aa3dc5e0e9c2dd19eacb05e515894e252d0886`, branch `star/mul-0-paper-to-code`, `integer-multiplication/openai-2026/{implementation-plan.md,sun-jobs.md,contracts/,evidence/}`. Shared `mul-v1.tsv` SHA256: `96e5ce0181dc92b269e444bc63c8f63684c56ad476474094b193ce4cd474f5f3`. This product corpus is an immutable input, not something to regenerate differently under its old name.
- **C — ComputerScience reading shelf:** `walnut-burgundy/computer-science@f1603a29e96f13ac0fb6c2eb8b4e3c1212749bbe`, retained PR #79, branch `bench/mul-number-theory-shelf-20261008`; target default branch `how-long+how-wide`.
- **F — Fulton:** `walnut-burgundy/fulton@f17fd6224da029f4f7c10a28b537a418b1e8aa7b`, retained PR #12, branch `books/algebraic-curves-multiplication-20261008`; target default branch `main`.
- **K — Seifert:** `isomorphismes/seifert@c19e1c4930e5121ed48ca98ecab443ac48f7e3db`, retained PR #7, branch `books/number-theory-multiplication-links-20261008`; target default branch `main`.
- **A — direct native Idriç:** `fuego-ironworks/idric-arm-thumb`, **native-arm**, inspected implementation-plan base `0ccef59e21415585c265b79360164f7351baa1c5`. `main` is the separate DEX line. Refresh and pin accepted ARM-1/ARM-2 successors before consuming generated native code.
- **P — paper source provenance, not an independent validation:** `openai/math@adc7f1241b42e322a6451854ab7e4b4c146bf78a`, `preprints/Integer-multiplication-below-n-log-n-September-23-2026/`. Use S's source-to-component mapping; do not silently substitute a conventional whole-input multiplication and call it the paper's path.

At start, inspect current related issues/PRs and retained branches. Reuse an existing owner rather than fork competing work. Make a fresh isolated worktree and the job's proposed branch from its pinned starting point plus explicitly accepted dependencies. Record the absolute checkout and every source, compiler, executable, input and dependency SHA in `dependencies.lock.json`. If heads advanced, preserve the intervening work and record the reconciliation. Never reset, force-push, merge a PR, close another owner's job, launch other agents, or provision paid infrastructure as part of these assignments.

Build maintained C through qualified ICK where available. Host GCC/Clang builds are independently labeled comparison/control lanes. Use the Android NDK when ICK lacks the required qualified target path, with the exact tested ICK revision and specific gap recorded. Never turn a host build into an ICK-code-generation claim. Keep the existing source ownership: compiler changes under `ick/source/`, never edit the immutable `gcc/` reference. Do not create another mathematical/numerical/machine IR, a new source syntax, or a duplicate arbitrary-precision runtime.

The current benchmark boundary is unsigned little-endian **arrays of 32-bit limbs**, independent of host byte order:

```c
int mul_candidate(const uint32_t *a, size_t na,
                  const uint32_t *b, size_t nb, uint32_t *out);
```

It requires positive lengths, preserved inputs, and the entire `na+nb`-limb output. Signed textual handling belongs to the wrapper. An optional versioned context/scratch API must adapt this contract, not silently change it. Legal aliasing, capacities and profile refusals must be explicit. Published-profile admission, reduced-model execution, baseline execution and expected refusals are distinct statuses.

**Timing rule:** generate inputs and exact expected products outside arithmetic-only timing. Preserve raw samples, not only rounded summaries. Compare the same operand bytes, not merely equal bit lengths. A different sample mode, compiler, machine, representation, profile or fallback path must have a different identity. Instrumented traces and uninstrumented speed measurements belong to separate builds/runs. Never reinterpret emulation as physical-device speed or extrapolate a finite fitted slope into an asymptotic theorem.

**Execution and evidence rule:** each check command named below is a required deliverable to implement unless already present; its presence is not asserted here. Commands run from the owning repository root. Each job's check driver must return nonzero for a failed assertion, crash, timeout, missing mandatory artifact, rejected candidate masquerading as success, or an undetected deliberately defective implementation. `assert` statements disabled by optimization must not be the sole acceptance mechanism. Emit a small machine-readable receipt, full commands, environment, stdout/stderr/statuses, hashes, successful cases and negative-control failures. Preserve partial work and explicitly distinguish PASS, FAIL, NOT_RUN, EXPECTED_REFUSAL and BLOCKED_EXTERNAL. Do not convert unavailable checks into successful checks.

**Parallel ownership:** MB-01 owns runner orchestration; MB-02 owns the shared C ABI/parser repair; MB-03 owns corpus bytes/schema; MB-06 owns raw timing schema/engine; MB-17 owns trace schema; MC-01 owns the shared reading index. Other jobs work in their named directories and provide minimal integration patches to those owners rather than simultaneously rewriting their files. MB-21 integrates benchmark deliverables into the existing MUL-6 qualification handoff; it does not replace MUL-6's authority over final algorithm/device qualification.

**Return:** PR/branch and exact head, reproducible command, accepted dependency pins, changed files, raw receipts, negative controls, remaining blockers, and the next consumer. The coordinator decides merging and subsequent dispatch. Costs of cloud rental, paid runners, new subscriptions or physical equipment require separate authorization; the user's request to use SUN allocation is not permission for such charges.

### Starting wave

Six new jobs have independent starts: **MB-01, MB-02, MB-03, MB-06, MB-17, MC-01**. Existing **MUL-1 and ARM-1** remain independently startable under their own instructions. Follow the coordinator's active-run limit; the job count is not a claim of concurrent execution.

## SUN MB-01 — Make real candidates testable and eliminate false passes

**Owner:** ICK at B. **Branch:** `sun/mb01-candidate-acceptance`.
**Dependencies:** none. **Start:** READY.

**Outcome and scope.** Replace the assumption that candidate acceptance always builds `candidate.example.c`. Add an explicit, recorded candidate source/build recipe or prebuilt executable selector; retain the example only as a clearly named smoke control. Keep the current `--pipe` protocol available. Build commands must be argument arrays, with compiler executable and flags separately recorded; do not execute arbitrary recipe strings through a shell. Own `benchmarks/bigmul/acceptance/` and runner changes, not the arithmetic component.

**Implementation.** Check exact output count, values, candidate identity, exit status and timeout for every corpus case. Test both normal Python and `python3 -O`. Include defective providers returning all zeroes, dropping a high limb/carry, reusing the preceding answer, exiting nonzero after valid output, printing extra output, hanging, or returning the correct answers through a disallowed oracle delegation. A provenance check must distinguish the last case from honest arithmetic equality; document its limits rather than treating a symbol-name check as a proof. Verify that an explicitly selected external binary is the one actually executed.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/acceptance/check_mb01.py`. The real provider-selection path must run the full existing corpus against an independent exact reference. Each defect must fail the outermost check process. Missing or unsupported real-candidate configuration must refuse rather than substitute the example. Preserve stdout and stderr on build failure. Return a JSON summary that names tested provider hashes and mutant outcomes.

**Exclusions/handoff.** Do not implement the new multiplier or rewrite the shared corpus. Hand the runner contract to MB-04, MB-05, MB-13 and MB-16. The existing six-test suite is a baseline, not proof that a future algorithm has been tested.

## SUN MB-02 — Enforce the C buffer, size and protocol contracts

**Owner:** ICK at B. **Branch:** `sun/mb02-abi-and-buffer-safety`.
**Dependencies:** none. **Start:** READY.

**Outcome and scope.** Harden the benchmark's shared C boundary and parser without changing the mathematical multiplication contract. Own guarded direct-call tests under `benchmarks/bigmul/abi/`, and the minimal necessary changes to `mulbench.c`. Coordinate runner changes with MB-01; do not rewrite its orchestration.

**Implementation.** Check every addition/multiplication used to allocate storage before it can overflow `size_t`, including 32-bit builds and caller-supplied lengths. Use portable format macros for `uint32_t`; include the required declared types instead of relying on accidental headers. Define input/output non-overlap, alignment and zero representation. Test input snapshots, nonzero-prefilled full output, guard words before/after buffers, leading-zero limbs and maximum-limb carries. Reject malformed/overlong text, extra operands, embedded NULs, missing operands, invalid signs and invalid numeric command-line limits according to a documented bounded protocol. Do not require the low-level kernel to detect a violation that its API cannot observe; validate such conditions in the checked wrapper.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/abi/check_mb02.py`. Run sanitizer builds where supported and separate ordinary 32/64-bit tests. Mutate an output store past the buffer, alter an input, omit upper zero writes and bypass an overflow check. They must be detected. Reject null pointers/lengths at the checked boundary without deliberately invoking undefined behavior. Fault-injected allocation failure must leave a nonzero status and no valid timing record.

**Exclusions/handoff.** No algorithm optimization and no new runtime library. Return the exact ABI plus a small reusable direct-call guard harness to MB-05, MB-11, MB-14 and MB-16. Unsupported sanitizer or 32-bit environments remain separately NOT_RUN, not full portability acceptance.

## SUN MB-03 — Build one reproducible, architecture-independent operand corpus

**Owner:** ICK at B; consume S unchanged. **Branch:** `sun/mb03-shared-corpus`.
**Dependencies:** none. **Start:** READY.

**Outcome and scope.** Add `benchmarks/bigmul/corpus/` containing deterministic generators, a documented wire format, manifest schema, fixture hashes and a streaming validator. Import S's `mul-v1.tsv` verbatim with its pinned hash. Additional families get new identities; do not replace that file under its old name.

**Implementation.** Each case records exact operand bytes, signed-wrapper versus unsigned-kernel semantics, mathematical bit lengths, stored limb lengths, generation parameters, seed/algorithm version, square/general-product distinction and case hash. Use a specified generator independent of Python's implementation-specific random sequence; changing suite order or maximum size must not change an existing case. Include 0/1, boundary widths `32k±1`, transform/padding thresholds when supplied, all ones, near powers of two, alternating blocks, separated nonzero limbs, equal values in different buffers, and varied random instances. Cover balanced and 2:1, 16:1, 256:1 and single-limb imbalance; retain operand order for asymmetric adapters. Define small/smoke/medium/large budgets rather than attempting all Cartesian combinations.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/corpus/check_mb03.py`. Repeated runs, reordered enumeration and different host word sizes must generate identical bytes for a case ID. Verify boundary definitions and advertised density/size. Corrupt a manifest hash, alter one operand, duplicate an ID and truncate a stream; validators must fail. Round-trip signs and leading-zero storage cases without conflating semantic and representation tests.

**Exclusions/handoff.** No timing or expensive search for exotic examples. Return the pinned corpus to MB-04 onward and a producer specification for MC-02 through MC-06. Large mathematical examples remain separate generated collections with explicit resource budgets.

## SUN MB-04 — Qualify independent exact oracles, including bc

**Owner:** ICK at B. **Branch:** `sun/mb04-independent-oracles`.
**Dependencies:** MB-01, MB-03. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Add independently built oracle adapters under `benchmarks/bigmul/oracles/`. Use `bc` as requested and Python integer arithmetic as a readily available second route; add GMP only as an explicitly identified independent route, never the candidate under another name.

**Implementation.** Discover and record the actual `bc` implementation/version, executable hash, base-setting semantics, multiline-output handling and exit behavior. Do not assume every command called `bc` is the same Berkeley implementation or has the same limits. Use explicit integer scale, uppercase hexadecimal operands and validated sign handling. Compare candidate output directly to independently obtained products, rather than only comparing two oracles to each other. Exhaust the 0..255 pairs with an efficient oracle route; require a documented cross-oracle sample including long carries and large operands. Support precomputed signed oracle manifests generated on a host for targets without Python/bc, with verifiable origin and content hashes.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/oracles/check_mb04.py`. Required-bc mode must fail when bc is unavailable; optional mode records the precise omitted coverage. Bad expected values, a stale oracle cache, blank output, extra results, a nonzero exit and an oracle timeout must not pass. Every performance case admitted later needs exact independently checked output, even when the second oracle is sampled.

**Exclusions/handoff.** Oracle generation time is not multiplier time; keep it outside arithmetic timing. Large products may use a separately qualified efficient oracle instead of forcing bc beyond its feasible budget, but state that explicitly. Hand oracle provenance, coverage and expected-product receipts to MB-13 and MB-16.

## SUN MB-05 — Add serious comparison implementations without hiding adaptation costs

**Owner:** ICK at B. **Branch:** `sun/mb05-baseline-providers`.
**Dependencies:** MB-01, MB-02, MB-03. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Add `benchmarks/bigmul/providers/` with the existing schoolbook baseline, a clearly identified conventional recursive baseline recovered from retained work where possible, and a pinned GMP adapter when supported. This is the baseline-provider deliverable for existing MUL-6, not a second production multiplication project.

**Implementation.** Read the installed GMP version's official low-level contracts. Respect actual limb width, supported length ordering, destination capacity, non-overlap and squaring entry points. Provide both semantic end-to-end comparison through the 32-bit harness interface and native-limb kernel comparison with conversion outside the measured interval. Mark these as different measurements. Record how high zeros, same-value distinct buffers and actual squaring are handled. Do not infer which internal GMP algorithm executed merely from an input size: record a verified threshold configuration, trace from a dedicated build, or UNKNOWN. If a small Karatsuba control is needed, keep it bounded, separately named and comprehensively checked; do not build another broad bigint library.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/providers/check_mb05.py`. All supported providers must pass identical corpus hashes and ABI guards. Test odd 32-bit limb counts on 64-bit GMP, swapped unbalanced arguments and zero products. A repacking/high-half mutant must fail. Record library license, build/configuration hash and linkage.

**Exclusions/handoff.** No claimed speed result from the schoolbook-forwarding example. No automatic algorithm selection in the compiler. Missing optional providers are explicit. Return comparable, individually named providers to MB-07 through MB-13 and MB-16.

## SUN MB-06 — Preserve raw timing samples and validate the measurement engine

**Owner:** ICK at B. **Branch:** `sun/mb06-measurement-engine`.
**Dependencies:** none for isolated module; MB-02 before shared-C integration. **Start:** READY_STANDALONE.

**Outcome and scope.** Implement a reusable timing module, sample schema and tests under `benchmarks/bigmul/timing/`; MB-02 remains owner of shared `mulbench.c` repairs. The standalone module can be built and tested before that integration.

**Implementation.** Preserve integer elapsed nanoseconds, repetition count, timer identity/resolution, process/trial order and raw batch records. Calibrate to a declared duration under explicit call/time limits; hitting a cap is recorded, not treated as reaching the duration. Collect wall and process/thread CPU time where available without confusing them. Keep input construction, reference multiplication and whole-output checking outside the timed interval. Use runtime data, an opaque call boundary and documented result consumption; inspect optimized/LTO builds for missing or hoisted arithmetic. A volatile one-word sink alone is not an acceptance argument. Measure an empty/control path separately; do not subtract noise into negative multiplication times.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/timing/check_mb06.py`. A deterministic fake clock checks calibration, overflow, zero duration, clock failure and summary formulas. Keep even-sample median and quantile conventions explicit. Quantiles across batch averages must be named batch quantiles, never per-request tail latency. An elided-call/control mutant and swapped time units must fail validation. Preserve raw data before producing summaries.

**Exclusions/handoff.** No performance threshold yet. Native-clock availability and instrumentation overhead are facts to record per platform. Deliver the sample contract to MB-07 onward and MB-12; after MB-02 freezes its interface, supply the minimal integration patch rather than rewriting its changes.

## SUN MB-07 — Hot kernel latency, squaring and scratch-reuse experiments

**Owner:** ICK at B. **Branch:** `sun/mb07-hot-kernel`.
**Dependencies:** MB-03, MB-05, MB-06. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Implement `benchmarks/bigmul/modes/hot/` using the shared providers, corpus and measurement engine. Measure repeated in-process arithmetic deliberately, with a clear boundary around everything included.

**Implementation.** Separate one repeated operand pair, a small rotating hot set, generic multiplication of equal-valued separate inputs, and an explicitly supported square path. Separate fresh candidate-owned scratch from reused/preallocated context; adaptation or allocation cannot disappear from the label. Use multiple deterministic operand instances and independent process launches. Run paired provider order in randomized blocks with replayable ordering. Sweep geometrically spaced sizes, word/padding/known dispatch boundaries ±1, and operand ratios. Cap the quadratic schoolbook range independently so it does not dominate the experiment budget. Record partial result validation and exact post-batch checks without timing the oracle.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/modes/hot/check_mb07.py`. Verify that every requested case and provider actually executes, the corpus hash stays fixed across providers, and workspace policy changes the result identity. A provider caching the last product, bypassing a call, or returning stale output must be caught by validation/control runs. Repeated-equal and square-specialized results must remain distinct. Report variability over independent runs, not just repeated calls in one batch.

**Exclusions/handoff.** Do not label this realistic request latency or cold-cache behavior. Produce the first same-machine schoolbook/conventional/GMP records with raw samples. Later MB-16 supplies the real paper-path candidate under the identical mode. Feed MB-12 and MB-21.

## SUN MB-08 — Mixed-request workloads, batching and sustained throughput

**Owner:** ICK at B. **Branch:** `sun/mb08-mixed-requests`.
**Dependencies:** MB-03, MB-05, MB-06. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Add a persistent-process workload mode under `benchmarks/bigmul/modes/mixed/`. Study changing operand sizes and content rather than timing one repeated multiplication.

**Implementation.** Define replayable workload files: uniform-sized varied pairs, small-heavy distributions with occasional large products, alternating large/small requests, long runs followed by a size change, and batches 1/8/64. Record warmup, arrival/scheduling policy, queue time if any, service time, throughput, request count and allocation policy. Default to a single worker so batching is not silently multithreading. Measure per-request latency only when timestamp overhead is characterized; separately offer batch-only throughput for tiny products. A closed-loop worker cannot produce an open-loop latency claim. Bound trace/corpus memory and preserve deterministic input order across candidates.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/modes/mixed/check_mb08.py`. Validate each output against the matching request ID and exact expected product. Drop, duplicate, reorder or reuse a response and force a mid-stream failure; the run must fail rather than summarize the surviving requests as complete. Inject a known deterministic delay fixture to test percentile accounting and distinguish service from queue time. Report sample counts and quantile conventions.

**Exclusions/handoff.** No distributed service or new networking stack. Do not claim p99 from seven batch averages. Publish raw workload/request receipts and mode-specific limits for MB-12, MB-13 and MB-21; integrate the real candidate only through MB-16's profile-aware provider.

## SUN MB-09 — Cache residency, first touch and working-set sweeps

**Owner:** ICK at B. **Branch:** `sun/mb09-cache-working-set`.
**Dependencies:** MB-03, MB-05, MB-06. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Add `benchmarks/bigmul/modes/cache/` to separate hot reuse, larger rotating operand pools, first-touch allocation, and deliberate cache-eviction preconditioning.

**Implementation.** Discover what can actually be observed about cache sizes, page sizes and memory limits. Use configurable working sets on both sides of those measured boundaries; never choose a fixed multi-gigabyte allocation for the phone. Distinguish input residency, output write allocation, scratch residency and code startup. Keep preconditioning outside arithmetic-only intervals and record its own cost separately. An eviction sweep is an attempted precondition, not proof of universally cold caches. Where permission allows, collect miss/fault/counter evidence with event names, scaling and multiplexing metadata. Otherwise label the condition operationally rather than inventing cache state.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/modes/cache/check_mb09.py`. Verify unique operand/working-set coverage and bounded allocation. A skipped preconditioner, reused supposedly fresh buffer and falsely repeated single operand must be observable in fixtures. Independent output checking remains mandatory after each timed sample. For first-touch results, distinguish page faults from multiplication cost. Missing hardware counters are NOT_AVAILABLE, never zero misses.

**Exclusions/handoff.** Do not drop system-wide caches, alter machine-wide settings, use privileged cache controls or force memory pressure on a shared host. No claim that a cache simulator measures the machine. Hand bounded experiments and operational cache-state descriptions to the native/Android/POWER lanes and MB-12.

## SUN MB-10 — End-to-end startup, parsing and representation costs

**Owner:** ICK at B. **Branch:** `sun/mb10-end-to-end-cost`.
**Dependencies:** MB-01, MB-02, MB-03, MB-05, MB-06. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Add `benchmarks/bigmul/modes/end_to_end/` for process-per-request and persistent-pipe measurements, separate from the arithmetic kernel.

**Implementation.** Measure launch-to-exit wall time, launch-to-first-result, parsing/import, allocation, arithmetic, export/formatting and I/O boundaries as supported. Include hexadecimal and binary interfaces first; decimal conversion is a separately named experiment. Use prebuilt binaries and pregenerated input files. Host-to-phone transfer or network RTT must not enter an on-device arithmetic label. Include an echo/parse-only control with the same protocol and byte sizes, but report its own distribution rather than subtracting medians as an exact decomposition. Record framing, buffering/flush policy, bytes in/out and output validation overhead.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/modes/end_to_end/check_mb10.py`. Test a slow-start fixture, a slow-output fixture and a valid-output/nonzero-exit fixture. A process that terminates early, truncates a large product or leaves extra buffered output must fail. Verify that decimal and hexadecimal inputs denote identical integers but remain different cost modes. Warm executable pages must not be described as a cold OS boot.

**Exclusions/handoff.** No changing the user's shell setup or device-installed software. No compiler build time inside request latency. Return operationally defined endpoint measurements, raw counts/statuses and conversion-versus-kernel comparisons to MB-12 and MB-21.

## SUN MB-11 — Allocation, peak memory and reusable workspace tradeoffs

**Owner:** ICK at B. **Branch:** `sun/mb11-memory-workspace`.
**Dependencies:** MB-02, MB-03, MB-05, MB-06. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Add `benchmarks/bigmul/memory/` with a measurement adapter for allocations, live bytes, peak workspace and process memory. Keep this profiling build separate from uninstrumented speed runs.

**Implementation.** Record requested heap bytes, live/peak tracked allocations, alignment, workspace lifetime and process RSS where available, with platform-specific units explicitly normalized. Use fresh processes to avoid mistaking a historical high-water mark for a per-case peak. Distinguish process RSS, candidate-owned workspace and exact bytes moved; one does not determine the others. Compare fresh scratch, reusable contexts and shrinking/growing operand sequences. Honor a configured resource budget and record anticipated storage before execution. Extend, do not replace, MB-02's allocation-failure tests.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/memory/check_mb11.py`. Validate counters against deterministic fixture allocators, including nested allocations, aligned storage, realloc growth/shrink and error cleanup. Missing platform RSS support is explicit. Instrumentation that changes candidate identity or excludes untracked memory must say so. A leak, incorrect unit conversion and failure-to-free-on-error mutant must fail the checker. Run workspace saturation/refusal tests under a small safe budget, not by exhausting host RAM.

**Exclusions/handoff.** No process-wide allocator replacement in unrelated applications. A versioned optional workspace interface requires MB-02/MB-16 agreement. Publish time-versus-memory tables only from properly paired run identities. Hand memory receipts to MB-12, MB-14 and MB-21.

## SUN MB-12 — Paired analysis, crossover detection and finite-range scaling

**Owner:** ICK at B. **Branch:** `sun/mb12-statistical-analysis`.
**Dependencies:** MB-03, MB-06; consume at least one accepted mode from MB-07 through MB-11 for real data. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Extend the existing `compare.py` through `benchmarks/bigmul/analysis/`, preserving raw provenance and rejecting incompatible comparisons. Produce a readable report plus machine-readable paired results.

**Implementation.** Require identical case hashes and compatible machine/compiler/provider/profile/mode identities. Reject duplicate rows and silently intersected partial suites unless the user explicitly requests a clearly labeled partial comparison. Analyze randomized process-level blocks, not millions of correlated calls as millions of independent observations. Report medians, spread, sample counts, ratio uncertainty and sensitivity to run order. Estimate local finite-range log slopes and candidate/baseline crossover intervals; label insufficient/no crossover data honestly. Include time divided by n, n log n, and selected conventional model functions only as diagnostic normalizations. Fit on one range and check held-out sizes rather than declare asymptotic complexity from a plot.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/analysis/check_mb12.py`. Synthetic fixtures must include known speedups, equal-speed noise, heteroscedastic data, outliers, missing rows, conflicting corpus hashes and changing machine identities. Validate medians/quantiles analytically on small vectors. Bootstrap or other uncertainty procedures must respect process/block grouping and expose their assumptions. Negative/NaN/infinite durations must fail.

**Exclusions/handoff.** No universal winner, automatic regression gate or beauty score. In particular, do not claim a tiny asymptotic exponent improvement can be inferred from available finite benchmarks. Return executable analysis and source-linked conclusions to MC-07 and MB-21.

## SUN MB-13 — Native x86-64/ARM64 CI, compiler lanes and durable receipts

**Owner:** ICK at B. **Branch:** `sun/mb13-native-ci-receipts`.
**Dependencies:** MB-01, MB-03, MB-04, MB-05, MB-06, MB-07. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Extend the existing `.github/workflows/bigmul-benchmark.yml`, not a competing workflow. Qualify native x86-64 and ARM64 and package replayable evidence under `benchmarks/bigmul/platforms/native/`.

**Implementation.** Preserve pinned external actions, exact triggering commit, least-privilege permissions and nonpersistent credentials. Verify actual runtime architecture, compiler executable/version/flags, linked library identity, CPU/ABI, OS, virtualization, available affinity and frequency/thermal facts. Separate qualified ICK, GCC and Clang lanes where available. Inspect generated multiply/carry code and unresolved helper symbols; do not infer acceleration from CPU marketing names. Use mandatory small correctness/mutant tests and bounded diagnostic timings; large experiments remain explicitly invoked. Retain raw samples, corpus/provider hashes, machine data, failures and toolchain/build receipts. Ensure artifact names include run/attempt/architecture and upload failure cannot yield a successful evidence gate.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/platforms/native/check_mb13.py` locally and the updated native workflow. Test a wrong-architecture label, stale artifact, missing mandatory bc qualification, forced candidate failure and interrupted timing upload. Each must be reported correctly. Source-only CI cannot claim the candidate executed on a target.

**Exclusions/handoff.** No paid runner upgrade or noisy wall-time regression threshold. A hosted ARM64 success is not MIRO ARM32 acceptance. Missing ICK qualification leaves that lane blocked while honestly labeled host controls proceed. Return exact CI job URLs and replayable archives for MB-21.

## SUN MB-14 — Prepare and execute physical MIRO A1 ARM32 benchmark acceptance

**Owner:** ICK at B; subordinate deliverable to existing SUN MUL-6, not a new qualification owner. **Branch:** `sun/mb14-miro-arm32`.
**Dependencies:** MB-01, MB-02, MB-03, MB-06, MB-07; actual paper-path results also require MB-16. **Start:** WAIT_FOR_DEPENDENCIES; PHYSICAL_RUN_REQUIRES_DEVICE.

**Outcome and scope.** Extend retained Android boundary deployment rather than create another shell bridge. Add `benchmarks/bigmul/platforms/android/` host-side build/deploy/collect commands that run a small prebuilt binary on the physical MIRO A1.

**Implementation.** Require explicit serial and inspect model, installed ABI, OS/API and executable compatibility. Preserve the intended ARM32/softfp/alignment contract; distinguish ICK A32 and direct-Idriç Thumb-2 experiments, and retain separate compiler/ISA labels. Prefer qualified ICK; otherwise use an identified NDK fallback with a specific ICK qualification gap. Compile on the host, not the phone. Transfer pinned inputs and precomputed oracle products, collect exact bytes and the remote process exit. Record battery/charging, thermal/frequency facts when accessible, run ordering and working-set budget. C67 or another phone is a separate record, never a substitute A1 success.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/platforms/android/check_mb14.py` for local transport fixtures; implement the explicit-serial device command in its help. Exercise wrong output, carry failure, exit 99, truncated response and disconnected transport through the same path. Missing physical access yields NOT_RUN physical receipts with tested host-side preparation.

**Exclusions/handoff.** No rooting, system setting changes, interactive build installs or unbounded heat/memory runs. Emulation may qualify code paths, not phone speed. Deliver baseline receipts first; rerun the same frozen cases after MB-16. Existing MUL-6 owns the final ICK/Idriç/device synthesis.

## SUN MB-15 — POWER and AIX portability with explicit rental approval

**Owner:** ICK at B. **Branch:** `sun/mb15-power-aix`.
**Dependencies:** MB-02, MB-03, MB-05, MB-06. **Start:** WAIT_FOR_DEPENDENCIES; NATIVE_AIX_REQUIRES_ACCESS.

**Outcome and scope.** Implement `benchmarks/bigmul/platforms/power/` with a capability probe, portable build/clock/receipt adapters and an AIX execution plan. Local portability fixtures are useful before a native account exists. POWER Linux, emulated POWER and native AIX are different qualification lanes.

**Implementation.** Verify installed compiler and 32/64-bit modes, byte order, integer/size_t widths, object format, timer semantics/resolution and available process-memory counters from that environment and current official IBM documentation. Do not assume Linux ELF/procfs/perf/getline behavior or an old XL flag applies to a different compiler. Test 32-bit little-endian limb serialization independent of machine endianness. Record LPAR/vCPU/SMT allocation and sharing information when visible. Build baseline providers, then the candidate only if its compiler/runtime path is qualified. Produce a present-day provider/access comparison only from verified sources; do not guess pricing or availability.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/platforms/power/check_mb15.py` for local tests and publish an explicit remote command taking an already-authorized host. Wrong-endian fixtures, timer-unit errors, unavailable mandatory libraries and masked remote failure must be detected. Native AIX acceptance requires native outputs, statuses and machine receipts. Cross-compilation or emulation alone is not acceptance.

**Exclusions/handoff.** Do not rent, reserve, subscribe, create a billable instance or spend money. No access means BLOCKED_EXTERNAL for native execution, while checked portability changes survive. Return an exact small proposed run envelope and shutdown/collection instructions for separately approved access; feed real receipts to MB-21.

## SUN MB-16 — Connect the actual paper-path implementation and prove its identity

**Owner:** ICK at B, consuming accepted SUN MUL-5 and the relevant MUL-1..4 component receipts. **Branch:** `sun/mb16-real-candidate`.
**Dependencies:** MB-01, MB-02, MB-03, MB-04, MB-05, MB-06, SUN MUL-5. **Start:** WAIT_FOR_REAL_IMPLEMENTATION.

**Outcome and scope.** Replace only the demonstration integration boundary with a real candidate adapter under `benchmarks/bigmul/providers/openai2026/`. Consume the existing `arithmetic/openai2026/` public API; do not reimplement the algorithm.

**Implementation.** Map 32-bit input limbs, output capacity, supported sizes, status codes, scratch/context and profile admission exactly. Record `reduced-algebra`, `published-fixed`, ordinary short-product provider and any baseline/fallback identity separately. Unsupported inputs must remain explicit refusals. A correct product from a whole-input GMP/Python/schoolbook bypass cannot count as execution of the paper-specific path. Use source/link provenance, stage-entry receipts and short-provider call dimensions/counts; validate these against the accepted implementation contracts. Keep trace validation in its instrumented lane and performance measurements in a matched uninstrumented lane, with corresponding build hashes.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/providers/openai2026/check_mb16.py`. Test admitted cases, expected refusals and a mutant that changes only the profile label, skips an essential stage, or delegates the entire product to a forbidden oracle. Value, admission, trace and provenance checks must all remain visible. A candidate binary must be explicitly selected by MB-01; the example is never a fallback.

**Exclusions/handoff.** No published-profile claim from an infeasible parameter set or conventional base case. Missing MUL-5 blocks this job's real acceptance, not earlier harness work. Return an immutable provider and its supported-domain manifest to every mode, platform lane, MB-19 and MB-21.

## SUN MB-17 — Add a trace format tied to operations that actually execute

**Owner:** ICK at B; conceptual cross-link to C/S. **Branch:** `sun/mb17-operation-traces`.
**Dependencies:** none for schema and executed baseline fixtures; actual candidate trace integration follows MB-16. **Start:** READY_STANDALONE.

**Outcome and scope.** Add `benchmarks/bigmul/traces/` with a versioned event format, event writer/validator, counters and small executed baseline traces. Build on `network_shape.py` instead of describing its idealized FFT topology as an implementation trace.

**Implementation.** Events distinguish semantic arithmetic, recursive subproducts, value/layout movement, buffers/lifetimes, transform layers, precision changes and provider calls. Include event units, coordinate space, word width, source/binary/profile/case identity and bounded payload references. Separate logical arrays from physical-address observations. Offer streaming counters and a bounded trace policy; if data is sampled/truncated, mark it and do not report a complete graph. Trace a small schoolbook implementation and a bounded existing recursive control; use fixtures for future paper-specific events without claiming they executed. Preserve higher-level math/numerical/machine distinctions rather than inventing a new compiler IR.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/traces/check_mb17.py`. Analytically check small multiplication operation counts and buffer lifetimes. Bad references, a dropped mandatory event, duplicate sequence number, unsupported units and a trace attached to the wrong executable must fail. Compare instrumented and uninstrumented output bytes for the same cases. Report the observer overhead in a separate experiment.

**Exclusions/handoff.** No claim that trace metadata alone proves compiler behavior. Trace values from the unexecuted future candidate remain fixtures. Freeze the format for MB-18, MB-19 and MB-20; coordinate real hooks with MB-16 and the existing MUL component owners.

## SUN MB-18 — Measure graph structure, permutations, cycles and layout dependence

**Owner:** ICK at B. **Branch:** `sun/mb18-algorithm-structure`.
**Dependencies:** MB-17. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Extend `network_shape.py` through `benchmarks/bigmul/structure/` with analyzers for actual MB-17 traces and separately labeled mathematical model fixtures.

**Implementation.** Compute arithmetic DAG depth under stated operation weights, fan-in/fan-out, recursive split shapes, layer sizes, distinct permutation maps and cycle histograms. Validate bijectivity before treating a map as a permutation. Distinguish graph invariants from traversal-order or memory-layout quantities such as stride and span. A relabeling may preserve cycle type and change locality; equivalent factorization schedules need not have the same physical traffic. Do not call the FFT itself merely a permutation or treat the bit-reversal map as its complete algorithm. Provide tiny exact traces for schoolbook/recursive multiplication and an independently executed small transform control, with explicit ring/normalization where needed.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/structure/check_mb18.py`. Keep the eight-point bit-reversal check (four fixed points and two transpositions) and add identity, long-cycle, nonbijective and differently labeled equivalent fixtures. Independently enumerate small graphs/permutations and verify computed depth/cycle results. Counterexamples must demonstrate at least one invariant unchanged while a layout statistic changes. Reject an incomplete trace as a complete structural signature.

**Exclusions/handoff.** No single aesthetic ranking. An annotated schedule/model is not evidence that the candidate used it. Return inspectable structural vectors and small example tables for MB-20, MC-07 and MB-21, with meaningful negative results rather than assumed distinctions.

## SUN MB-19 — Trace carries, intermediate precision and recovery margins

**Owner:** ICK at B, consuming existing MUL numerical component contracts. **Branch:** `sun/mb19-precision-carry-evidence`.
**Dependencies:** MB-03, MB-17; actual paper-path acceptance additionally MB-16. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Implement `benchmarks/bigmul/precision/` with well-defined carry/width statistics and independent validation of emitted recovery certificates. Do not replace MUL-3/MUL-4's numerical implementations or error proofs.

**Implementation.** Distinguish an operand's bit pattern from the realized carry process of a particular implementation. Define carry count, longest serial carry segment and normalization passes using an explicit digit base and scan semantics. For candidate stages, record maximum intermediate magnitude/width, Gaussian component widths, declared precision, truncation location, certified error bound and distance of a recovery value from an ambiguous rounding boundary. Separate measured discrepancies against a higher-precision reference from rigorous interval/certificate bounds. Unknown bounds remain unknown, not zero. Count scratch restoration separately from numerical coefficient recovery.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/precision/check_mb19.py`. Exhaust small radix/short-digit examples against an independent direct computation. Include all-ones products, near powers, signed packed coefficients and values near a rounding boundary. Drop a carry, change a truncation location, relax a bound and falsely claim scratch restoration; each relevant checker must fail. Verify trace-disabled and trace-enabled products agree.

**Exclusions/handoff.** No theorem obtained by sampling; no floating approximation presented as exact certification. Without MB-16, accept only the executed baseline portion and fixture validator. Return algorithm-specific carry/precision signatures and checked candidate certificates to MB-21 and MC-07.

## SUN MB-20 — Separate tape-model costs, RAM operations and memory locality

**Owner:** ICK at B; source mapping at S. **Branch:** `sun/mb20-cost-models`.
**Dependencies:** MB-17, MB-18. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Add `benchmarks/bigmul/cost_models/` with explicit model definitions and checked cost accounting for small execution traces. This consumes, rather than reimplements, the paper's network components from SUN MUL-1..4.

**Implementation.** Keep at least three distinct outputs: observed native wall/CPU time; counted word/RAM operations and logical bytes; and steps charged by a specified finite-alphabet fixed-tape model. Charge descriptor/constant preparation, bit widths, address movements and scratch work, not only butterfly arithmetic. If a routine is opaque, mark its cost unresolved rather than assigning zero. A bounded cache simulator may add a separate locality model with line size/associativity/replacement assumptions; its misses are not hardware counter observations. Preserve input/output/transition contracts, and publish exactly which operations the model simulates versus symbolically counts.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/cost_models/check_mb20.py`. Hand-enumerated tiny copy, transpose, permutation and scalar-network schedules must match model counts. Equivalent value computations with different movement schedules should demonstrate correctly different charged costs. Mutate a move, omit preparation, change word width or substitute an uncharged lookup table; checks must detect invalid accounting. Compare trace totals to independently accumulated per-stage totals.

**Exclusions/handoff.** Do not retrofit a RAM array transpose with the paper's tape bound, claim a practical speedup from a symbolic exponent, or attempt infeasible published-size materialization. Return named model descriptors, unresolved costs and small checked comparisons to MB-21 and the STAR research evidence directory.

## SUN MB-21 — Integrate the benchmark package and hand evidence to MUL-6

**Owner:** ICK at B; final implementation/device owner remains existing SUN MUL-6. **Branch:** `sun/mb21-benchmark-delivery`.
**Dependencies:** MB-01..MB-13, MB-16; MB-14/MB-15 execution results or explicit external blockers; MB-17..MB-20 accepted scoped artifacts. MC jobs are optional follow-on corpus additions. **Start:** WAIT_FOR_ACCEPTED_BENCHMARK_COMPONENTS.

**Outcome and scope.** Integrate accepted benchmark modules and their exact dependency pins into the retained harness line, resolve shared-file changes with their owners, and deliver a runnable acceptance/report command before the implementation's final merge decision. Do not start a second qualification workflow outside MUL-6.

**Implementation.** Add a dependency-aware suite driver under `benchmarks/bigmul/release/`. Require actual-candidate selection, independent exactness, mutant rejection, identical-input paired timing and source/profile/compiler/machine receipts. Run at least the bounded hot and mixed modes with serious conventional baselines on available native machines. Produce separate coverage grids for arithmetic correctness, measured performance, trace/cost evidence and physical targets. Preserve expected profile refusals. Include memory and startup/cache modes where executed, and show NOT_RUN cells rather than removing them. Re-run after integration; child successes alone do not establish the combined head works.

**Acceptance and command.** Implement/run `python3 benchmarks/bigmul/release/check_mb21.py`. A deliberately wrong product, stale source hash, missing mandatory corpus, substituted example provider and absent essential stage receipt must each fail the package gate. A missing AIX machine must not be reported as a pass or prevent an explicitly narrower native-only report; define required target profiles rather than silently weakening them. Archive exact raw results and reproduction commands.

**Exclusions/handoff.** No merge, auto-selection policy or unsupported headline speedup. No dependency on finishing every optional book-derived corpus. Return one benchmark-readiness receipt to SUN MUL-6, and identify exactly what still blocks the chosen implementation/device acceptance profile.

## SUN MC-01 — Reconcile the reading shelves and source-to-workload map

**Owner:** ComputerScience at C; coordinate retained Fulton F and Seifert K changes. **Branch:** `sun/mc01-reading-provenance` in each touched repository.
**Dependencies:** none. **Start:** READY.

**Outcome and scope.** Maintain the existing shelves rather than copy books indiscriminately. Reconcile ComputerScience `books/`, Fulton `sources/fulton-algebraic-curves/`, and Seifert `books/` with reciprocal links and a source-to-computation manifest.

**Implementation.** Verify author/title/edition and legal author/publisher/DOI access for Silverman's *A Friendly Introduction to Number Theory*, Ash/Gross's *Elliptic Tales*, Fulton's *Algebraic Curves*, Morishita's *Knots and Primes*, and the already proposed arithmetic-geometry references. Resolve the user's separate phrase *Plane Algebraic Curves* from repository/history and authoritative records; do not silently identify it with Fulton or invent a chosen author. An unresolved title remains explicitly unresolved. Preserve source credits and redistribution rules. Link-only entries are acceptable where reproduction rights are absent. Distinguish works merely catalogued from chapters actually read.

**Acceptance and command.** Implement/run `python3 integer-multiplication/workloads/reading/check_mc01.py` in ComputerScience. Validate unique bibliographic IDs, reachable canonical cross-links as available, and a concrete mapping from a cited section/example to a proposed finite arithmetic object. Each of MC-02..MC-06 receives at least a usable source trail or an explicit source-access blocker. Missing source text cannot be filled by invented page references. Cross-repository mutations retain their own SHA receipts.

**Exclusions/handoff.** No book-length summaries, copyrighted PDF mirroring without permission, or claim that cataloguing generated benchmark data. Deliver reading prerequisites for the five mathematical generators; these jobs are future detailed study, not all the mathematical derivation crammed into this one assignment.

## SUN MC-02 — Elementary number-theory families with exact generators

**Owner:** ComputerScience at C, exporting MB-03-compatible data. **Branch:** `sun/mc02-number-theory-corpus`.
**Dependencies:** MC-01, MB-03. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Add `integer-multiplication/workloads/elementary/` with source-grounded integer families, exact generators, small worked examples and hashed operand pairs. Make the definition of each number visible instead of storing unexplained literals.

**Implementation.** Study repunits in several bases, near powers, evaluated cyclotomic polynomials, Fibonacci/Lucas and Pell-type recurrences, factorials/primorials, and binomial coefficients. Choose a bounded useful subset with contrasting bit/limb structure; do not maximize family count for its own sake. Record factorization or primality only when actually established and relevant. Pair each family with same-size random or density-matched controls, with exact generator parameters and output-size budgets. Keep generation outside timing, and separate sequential arithmetic workloads from individual multiplication snapshots.

**Acceptance and command.** Implement/run `python3 integer-multiplication/workloads/elementary/check_mc02.py`. Check small values through two independent routes: for example direct sums versus recurrence, iterative multiplication versus an independently implemented combinatorial identity. Verify advertised bit lengths and MB-03 hashes, signs and pair identities. Mutate a recurrence coefficient, an index and a base; tests must fail. Include at least one nontrivial family whose speed is not assumed to differ from its controls.

**Exclusions/handoff.** Do not claim prime or geometrically meaningful integers must multiply faster or slower. No expensive open-ended prime search. Return a bounded manifest with derivations and provenance to MC-07 and MB-21's optional corpus intake; do not alter the basic smoke corpus.

## SUN MC-03 — Elliptic-curve arithmetic as genuine integer workloads

**Owner:** ComputerScience at C, cross-linked to F. **Branch:** `sun/mc03-elliptic-workloads`.
**Dependencies:** MC-01, MB-03. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Add `integer-multiplication/workloads/elliptic/` with explicitly checked curves/points and integer operand pairs taken from actual calculations, guided by *Elliptic Tales* and more technical sources as needed.

**Implementation.** Choose small nonsingular curves and verified points; derive bounded sequences of additions/doublings, projective-coordinate products, or rational numerator/denominator growth. Verify the curve equation and exact representation at every step. Label integer products separately from modular field multiplication, inversion/reduction and complete point operations. Compare formulas only with their operation/exception contracts intact; include the point at infinity, inverse pairs, doubling exceptions and zero denominators. Record changing bit lengths, coordinate height and whether squaring occurs. A field residue is not automatically a point coordinate.

**Acceptance and command.** Implement/run `python3 integer-multiplication/workloads/elliptic/check_mc03.py`. Use a genuinely independent exact reference, not the same point-operation function called twice. Check small group identities within the admitted domain and every extracted integer product against the MB-04 oracle route when available. An off-curve point, singular curve, altered sign and skipped modular reduction in a field-level fixture must be rejected. Regenerated manifests must be byte-identical.

**Exclusions/handoff.** No cryptographic key material, security claims, or new elliptic-curve library for production. Keep full point-operation timing outside the plain-integer benchmark labels. Return source derivations, verified operand manifests and equivalent-size controls to MC-07; F receives source links, not a duplicate generator implementation.

## SUN MC-04 — Fulton polynomial arithmetic, safe packing and resultants

**Owner:** Fulton at F; export corpus records to ComputerScience/ICK formats. **Branch:** `sun/mc04-polynomial-workloads`.
**Dependencies:** MC-01, MB-03. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Add `experiments/multiplication/polynomials/` beside the existing Fulton source structure. Derive bounded polynomial coefficient, resultant and discriminant workloads with an explicit conversion from algebraic objects to finite integers.

**Implementation.** Implement a checked packing/unpacking experiment for integer polynomial multiplication. Prove the coefficient bound needed for the chosen radix, lengths and sign encoding; positive packing alone is not sufficient for signed coefficients. Keep degree, support, coefficient height and normalization metadata. Start with direct convolution as an independent oracle, then calculate small resultants through a Sylvester determinant and a separate algebraic route or symbolic reference. Derive discriminants with the correct degree/leading-coefficient factors and sign convention. Use modest singular/nonsingular and sparse/dense examples with precisely cited source concepts; document additional constructions as original experiments rather than falsely attributing them to Fulton.

**Acceptance and command.** Implement/run `python3 experiments/multiplication/polynomials/check_mc04.py`. Test negative coefficients, zero/constant polynomials, leading zeros, high coefficient growth and insufficient radix width. Deliberate carry overlap, a wrong discriminant sign and dropped leading-coefficient factor must fail. Compare packed multiplication with coefficient-wise exact convolution; report integer-kernel cost separately from packing and polynomial end-to-end cost.

**Exclusions/handoff.** No arbitrary machine integer declared a curve invariant. No algebraic-geometry engine redesign. Return proved encoding bounds, executable examples, fixture hashes and provenance; give MC-07 matched controls and cross-link the canonical derivation from ComputerScience without duplicating it.

## SUN MC-05 — Seifert matrices, Alexander data and arithmetic-topology examples

**Owner:** Seifert at K, exporting ComputerScience-compatible manifests. **Branch:** `sun/mc05-seifert-arithmetic-workloads`.
**Dependencies:** MC-01, MB-03; consume MC-04 only when using its packing format. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Add `experiments/multiplication/` for source-checked knot/Seifert examples and a careful arithmetic-topology bridge. This is a mathematical workload generator, not a rewrite of the interactive ribbons.

**Implementation.** Start from documented small Seifert matrices and independently verify the convention for `det(V - t V^T)`, normalization, units and knot-versus-link assumptions. An arbitrary integer matrix must be labeled an algebraic fixture unless realized/certified as Seifert data. Produce bounded polynomial products, evaluations or cyclic-resultant examples with known definitions, coefficient bounds and exact operand extraction. Use Morishita to select one genuinely finite arithmetic example, such as a specific residue-symbol computation, only after verifying the relevant hypotheses. Clearly separate analogy from equality and plain multiplication from modular arithmetic. Reuse MC-04 packing only with its accepted bound/sign contract.

**Acceptance and command.** Implement/run `python3 experiments/multiplication/check_mc05.py`. Compare determinant/polynomial values by independent methods on small examples. Test convention changes and expected normalization invariance without erasing meaningful signs. A malformed matrix, incorrect transpose, insufficient packing width or unsupported topology claim must fail its respective validator. Regenerate exported integer-pair hashes exactly.

**Exclusions/handoff.** Do not infer an invariant from an unclosed dragged ribbon, invent knot realizability, or assert that primes are literally knots. Return precise source examples, calculations, bounded manifests and honest unresolved realizability/source questions to MC-07 and the existing Seifert books index.

## SUN MC-06 — Arithmetic-geometry and number-field size-growth workloads

**Owner:** ComputerScience at C, source links from the reconciled shelf. **Branch:** `sun/mc06-arithmetic-geometry-workloads`.
**Dependencies:** MC-01, MB-03. **Start:** WAIT_FOR_DEPENDENCIES.

**Outcome and scope.** Add `integer-multiplication/workloads/arithmetic_geometry/` with a small number of genuinely derived finite arithmetic experiments, not a general survey. Keep its ownership separate from MC-03 elliptic points and MC-04 polynomial packing.

**Implementation.** Choose explicitly presented small-degree number fields/orders with verified defining-polynomial assumptions and a declared basis. Derive products, norm/trace calculations or height-driven numerator/denominator sequences from a cited example. Record whether a quantity is an algebraic integer, a field element, a matrix entry or an ordinary integer; only a documented extraction yields a plain integer multiplication case. Account for basis changes and denominator clearing. Use norms computed from a multiplication matrix against a separate conjugate/resultant route on small examples; distinguish irreducibility from a mere random polynomial. Study how sizes and imbalance evolve along an actual calculation.

**Acceptance and command.** Implement/run `python3 integer-multiplication/workloads/arithmetic_geometry/check_mc06.py`. Verify small definitions and independent norm/trace identities under their hypotheses, with exact arithmetic. Mutate a basis coordinate, denominator, defining polynomial or an unproved irreducibility assertion and require rejection or appropriately downgraded labeling. Enforce degree/height/output-bit budgets before expanding huge intermediate objects. Hash every admitted operand pair and provenance record.

**Exclusions/handoff.** No theorem about an infinite family inferred from examples, no copied textbook solution presented as original research, and no claim that sophisticated provenance necessarily changes multiplication speed. Return concrete worked examples and manifests to MC-07, with source-access gaps honestly marked.

## SUN MC-07 — Test which mathematical structures actually change execution

**Owner:** ComputerScience at C; consume benchmark receipts, not a forked harness. **Branch:** `sun/mc07-structure-versus-performance`.
**Dependencies:** MB-03, MB-07, MB-12, MB-18; MB-19 for precision/carry claims; accepted outputs from at least two of MC-02..MC-06. **Start:** WAIT_FOR_DATA.

**Outcome and scope.** Add `integer-multiplication/workloads/analysis/` with a reproducible matched experiment and a source-linked report connecting mathematical provenance, operand representation, algorithm structure and measured costs.

**Implementation.** For each chosen family, state the proposed computational mechanism before examining timings: density, long carry patterns, imbalance, squaring, transform padding or another testable property. Match controls on exact bit lengths, operand ratio and relevant bit/limb features. Vary one property where possible; retain a held-out parameter/size range and randomized provider/process order. Compare structure vectors from MB-18 and actual carry/precision data from MB-19 separately from native time/memory. Source mathematics may explain how operands arise without explaining a speed difference. Include negative results when a fixed-size implementation follows the same path for all families.

**Acceptance and command.** Implement/run `python3 integer-multiplication/workloads/analysis/check_mc07.py`. Use a synthetic known-effect dataset and a no-effect dataset to validate pairing, report generation and uncertainty handling. Reject mixed machine identities, missing controls and labels that leak the measured outcome into the hypothesis. Trace every table row back to a corpus hash, provider, machine, raw sample and mathematical derivation. Clearly distinguish observed association from a demonstrated mechanism.

**Exclusions/handoff.** No beauty score, significance fishing, universal architecture ranking or inference of the paper's asymptotic exponent. Report which notions of mathematical interest are visible to a multiplier and which remain meaningful only at the generating-workload level. Publish the final research evidence in ComputerScience and cross-link Fulton/Seifert; this is optional follow-on research, not a blocker for MB-21's first implementation-readiness receipt.

## Source and ownership links

- Benchmark code/retained PR: https://github.com/dilapidated-shed/ick/pull/82
- Existing eight implementation assignments, fixed source: https://github.com/walnut-burgundy/computer-science/blob/32aa3dc5e0e9c2dd19eacb05e515894e252d0886/integer-multiplication/openai-2026/sun-jobs.md
- Reading shelf: https://github.com/walnut-burgundy/computer-science/pull/79
- Fulton source: https://github.com/walnut-burgundy/fulton/pull/12
- Seifert cross-links: https://github.com/isomorphismes/seifert/pull/7
- GMP multiplication algorithm reference (verify version used): https://gmplib.org/manual/Multiplication-Algorithms
- GMP low-level interface reference: https://gmplib.org/manual/Low_002dlevel-Functions
- GNU bc provenance/reference: https://www.gnu.org/software/bc/
- FreeBSD bc manual: https://man.freebsd.org/cgi/man.cgi?query=bc&sektion=1
- IBM AIX processor timer documentation: https://www.ibm.com/docs/en/aix/7.2.0?topic=management-accessing-processor-timer
- IBM AIX clock documentation: https://www.ibm.com/docs/en/aix/7.1.0?topic=c-clock-getres-clock-gettime-clock-settime-subroutine

These links supply source provenance and contracts, not evidence that the new jobs have executed. Prepared assignments and actual dispatch/run receipts must remain separate.
