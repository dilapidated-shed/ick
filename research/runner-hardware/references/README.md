# Runner hardware source locators

The source hashes, retrieval dates, available revisions, staged artifact names,
and acquisition outcomes live in the existing
[`references.tsv`](../references.tsv). Full downloads stay in the ignored local
`references/.staging/` directory; vendor manuals and source archives are not
committed. These links and locators identify material for later inspection;
they do not choose a fetch width, SIMD policy, or numeric representation.

The corrected [runner execution](https://github.com/dilapidated-shed/ick/actions/runs/36399380725)
has three fingerprints: [sample 1](../fingerprints/36399380725-1-1/README.md)
reports one AMD EPYC 7763 guest; [sample 2](../fingerprints/36399380725-1-2/README.md)
and [sample 3](../fingerprints/36399380725-1-3/README.md) report Intel Xeon
Platinum 8573C guests. Processor specifications and
vendor manuals describe processors. They do not establish the VM's physical
memory channels, cache ownership, or achievable bandwidth. The exact Intel
8573C guest SKU remains unverified; the compiler target string is not a SKU
confirmation.

## GitHub

- [Hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners): standard runner allocation table and VM-per-job description; compare public and private repository rows for `ubuntu-24.04` x64. The page has no immutable revision.
- [Ubuntu 24.04 image inventory at commit `055a621`](https://github.com/actions/runner-images/blob/055a621061058268af5c62abada4bd7150afd5f1/images/ubuntu/Ubuntu2404-Readme.md): header fields `OS Version`, `Kernel Version`, and `Image Version`; the inspected image says `24.04.5 LTS`, `6.17.0-1022-azure`, and `20260920.314.1`. This pins the software image record, not the allocated processor.

## AMD

- [EPYC 7763 product specifications](https://www.amd.com/en/products/processors/server/epyc/7003-series/amd-epyc-7763.html): product-level cache and memory specifications. Apply only to the named processor specification; do not project them onto the runner VM.
- [Software Optimization Guide for AMD EPYC 7003 Processors, document 56665](https://docs.amd.com/v/u/en-US/56665), revision 3.00, November 2020. The publisher ZIP is at the [direct document endpoint](https://docs.amd.com/api/khub/documents/evLVi6~ZqtLjeStmBSVThA/content). In the PDF `56665_3.00.pdf`, inspect §2.2 “Cache Line, Fetch and Data Type Widths” (pp. 20–21); §2.6 “Processor Cache Operation” (pp. 24–26); §2.7 “Memory Address Translation” (pp. 26–28); §2.12 “Load-Store Unit” and §2.12.1 “Prefetching of Data” (pp. 46–49); and §2.13 “Optimizing Writing Data” (pp. 49–52). This is Family 19h guidance, not evidence of the runner's physical memory configuration.
- [High Performance Computing Tuning Guide for AMD EPYC 7003 Series Processors, document 70574](https://docs.amd.com/v/u/en-US/high-performance-computing-tuning-guide-amd-epyc7003-series-processors): the page lists revision 1.0 dated 2022-03-21. **Acquisition failed safely:** its document link resolves to a PDF cover identifying publication 57091 revision 4.0, rather than requested document 70574. The mismatched PDF was not retained or used, and no section locators are asserted for 70574.

## Intel

- [Optimization Reference Manual Volume 1, v50](https://www.intel.com/content/www/us/en/developer/articles/technical/intel64-and-ia32-architectures-optimization.html) links to the [downloaded Volume 1 PDF](https://cdrdv2.intel.com/v1/dl/getContent/671488), document 248966-050US. Useful index locators: §2.2 Sapphire Rapids overview (pp. 2-5 onward; only family context); §3.6.9–3.6.11 write combining, locality, and non-temporal store traffic (pp. 3-54–3-56); §3.7 prefetching (pp. 3-57–3-65); §9.3–9.6 prefetch, streaming loads/stores, software prefetch scheduling, and non-temporal stores (pp. 9-2–9-32); §22.8.5–22.8.7 cache misses and TLB miss ratios (pp. 22-73–22-74); Appendix B.1–B.2 TLB misses (Appendix pages B-1 onward). These cross-generation materials are not proof that the guest is a Sapphire Rapids SKU.
- [5th Generation Intel Xeon Scalable family page](https://www.intel.com/content/www/us/en/products/details/processors/xeon/5th-gen-xeon-scalable-processors.html): family-level reference only. No exact 8573C product specification was accepted as authoritative in this acquisition; keep its identification qualified.

## Linux kernel

- [CPU topology interface](https://docs.kernel.org/admin-guide/cputopology.html#how-cpu-topology-info-is-exported-via-sysfs): describes guest-visible topology under `/sys/devices/system/cpu/cpuX/topology/` and its architecture-neutral attributes.
- [Stable sysfs ABI](https://docs.kernel.org/admin-guide/abi-stable-files.html): relevant path locators include `/sys/devices/system/cpu/online`, `/sys/devices/system/cpu/possible`, `/sys/devices/system/cpu/cpuX/topology/core_cpus_list`, `/sys/devices/system/cpu/cpuX/topology/package_cpus_list`, `/sys/devices/system/cpu/cpuX/cache/indexY/` attributes, `/sys/devices/system/node/online`, and `/sys/devices/system/node/nodeX/{cpulist,meminfo}`. These match the globbed sysfs evidence in [the runner probe](https://github.com/dilapidated-shed/ick/blob/dmd-runner-memory-research/.github/workflows/runner-hardware.yml#L61-L75). The probe also records `/proc/cpuinfo`, `/proc/self/numa_maps`, and `lscpu`; those remain guest/process reports.

## Compiler documentation and LDC source

- [LLVM `llc` guide](https://llvm.org/docs/CommandGuide/llc.html): [`-mtriple`](https://llvm.org/docs/CommandGuide/llc.html#cmdoption-llc-mtriple), [`-march`](https://llvm.org/docs/CommandGuide/llc.html#cmdoption-llc-march), [`-mcpu`](https://llvm.org/docs/CommandGuide/llc.html#cmdoption-llc-mcpu), and [`-mattr`](https://llvm.org/docs/CommandGuide/llc.html#cmdoption-llc-mattr). These select code-generation target inputs; they do not identify or control physical guest memory topology.
- [DMD Linux switches](https://dlang.org/dmd-linux.html#switch-mcpu): `-mcpu=baseline|avx|native` and its help form. This is DMD's documented switch, not LDC's complete LLVM target-feature interface.
- [LDC official source at exact commit `ac0e420`](https://github.com/ldc-developers/ldc/tree/ac0e420af3fe74de50ff2138f9ffcb464c29873a), consulted 2026-09-28. The pinned source archive and selected source files are in the ledger. The bundled DMD-front-end CLI table in [`dmd/cli.d`](https://github.com/ldc-developers/ldc/blob/ac0e420af3fe74de50ff2138f9ffcb464c29873a/dmd/cli.d#L683-L699) lists compatibility choices (`baseline`, `avx`, `avx2`, `native`); [`tests/driver/gh2073.d`](https://github.com/ldc-developers/ldc/blob/ac0e420af3fe74de50ff2138f9ffcb464c29873a/tests/driver/gh2073.d#L1-L3) exercises LDC's `-mcpu=help` and `-mattr=help`; [`driver/ldmd.cpp`](https://github.com/ldc-developers/ldc/blob/ac0e420af3fe74de50ff2138f9ffcb464c29873a/driver/ldmd.cpp#L619-L629) locates DMD-compatible CPU-option forwarding. Use LLVM's `-mattr` documentation for feature-option meaning; do not read the DMD-compatible list as the full LDC interface.
