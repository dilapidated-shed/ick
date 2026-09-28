# Hardware knowledge map — 2026-09-28

Statuses describe the **standard public `ubuntu-24.04` x64 GitHub VM**,
not an owned physical server. Reclassify guest rows after committing actual
probe artifacts. A guest report never becomes a GitHub guarantee.

| Topic | Current class | Basis and next question |
| --- | --- | --- |
| VM label, x64, four allocated CPUs, 16 GB RAM, 14 GB SSD | KNOWN FROM DOCUMENTATION | GitHub runner reference; applies to this public repository. |
| Ubuntu 24.04 label and VM-per-job model | KNOWN FROM DOCUMENTATION | GitHub reference; exact image revision/kernel remain run-specific. |
| Exact CPU vendor/model/family and exposed flags | CURRENTLY UNKNOWN | Collect `cpuinfo`, `lscpu`, compiler target reports for independent jobs. |
| Guest-visible CPU and cache topology, line size and sharing masks | CURRENTLY UNKNOWN | Collect sysfs and `lscpu`; reported descriptors may be virtualized. |
| Guest page size, huge page settings, NUMA nodes | CURRENTLY UNKNOWN | Collect `getconf`, sysfs and process NUMA map; distinguish node presentation from real host topology. |
| Physical DIMMs, channel count/width, clock and controller configuration | PROBABLY NOT OBSERVABLE ON GITHUB-HOSTED RUNNER | No promise in runner docs; a model's nominal channel specification does not identify guest allocation. |
| Effective sustained streaming throughput for large working sets | REQUIRES MEASUREMENT | Controlled later benchmark, allocation-specific fingerprint and noise/repetition. |
| Useful fetch grouping and cache-line utilization with packed dimensions | REQUIRES MEASUREMENT | Need layouts/access traces and working-set sweep, no chosen fetch width here. |
| Outstanding misses and memory-level parallelism available to this guest | REQUIRES MEASUREMENT | Vendor guides offer host mechanisms, but no guest-specific guarantee. Performance counters may be blocked. |
| Effective SIMD width, downclocking and load/store throughput | REQUIRES MEASUREMENT | CPUID/compiler flags show available instructions only; disassembly and measured throughput needed. |
| Packed E5M3 byte storage and explicit widening semantics | KNOWN FROM DOCUMENTATION | Existing ICK contract; whether an actual D kernel benefits remains unmeasured. |
| DMD/LDC/GDC generated instruction sequences and vectorization | REQUIRES MEASUREMENT | Pin exact compilers and inspect generated assembly before attributing performance. |
| Physical prefetcher policy, host cache contention and host memory placement | PROBABLY NOT OBSERVABLE ON GITHUB-HOSTED RUNNER | Performance can reflect these effects; guest cannot identify the host state reliably. |

## Next bounded Sol research job

After at least three independent runner artifacts are committed, identify
each observed CPU family and select its matching vendor optimization
references. Define one tiny D/Icky D streaming kernel family with fixed
semantic output and explicit data layouts; inspect DMD and LDC machine code
before comparing throughput. Vary working-set size and access concurrency
with repeated allocations and preserve raw timings under the cited
fingerprint. Determine what measurements can separate cache/translation,
load issue, and external memory limits; record confounding scheduling and
virtualization effects. Keep E5M3 storage semantics separate from the
question of arithmetic widening. Do not choose a winning fetch or vector
width until the evidence supports one.
