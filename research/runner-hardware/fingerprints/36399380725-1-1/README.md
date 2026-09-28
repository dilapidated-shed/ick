# Sample 1: normalized guest fingerprint

- Provenance: [workflow run 36399380725](https://github.com/dilapidated-shed/ick/actions/runs/36399380725), attempt 1, matrix sample 1; [original artifact 10959980036](https://github.com/dilapidated-shed/ick/actions/runs/36399380725/artifacts/10959980036).
- Checkout source: pull-request synthetic merge `6ae8adf6a18a5d2677411ebbe458547eb496212c`; actual PR head `9704eebfd35883783b316a3955981c2aa489e4a5`. Identification code is independent of checkout.
- Label and date: `ubuntu-24.04`; 2026-09-28T08:46:37Z.
- Guest OS/kernel: Ubuntu 24.04 label; `6.17.0-1022-azure`; x86_64.
- Guest CPU: AMD EPYC 7763; 25/model 1/stepping 1; 4 logical CPUs, reported 2 cores × 2 threads × 1 socket, one reported NUMA node.
- Guest cache: L1d 32 KiB per reported instance ×2; L1i 32 KiB ×2; L2 512 KiB ×2; L3 32 MiB ×1; 64-byte coherency line reported for all levels. These descriptors do not prove the guest owns the whole cache.
- Compiler-visible features: AVX2, FMA and F16C present; AVX-512 absent; GCC native target znver3.
- Guest virtualization: Microsoft hypervisor, full virtualization as reported by `lscpu`.
- Guest memory/page: `MemTotal 16373452 kB`; 4096-byte base page, zero preallocated huge pages in raw `meminfo`.
- Unknown: physical CPU allocation, host siblings, DIMMs/channels/speed, host NUMA location, effective cache share, bandwidth, load concurrency, sustained vector width/throughput and access to performance counters.
- Exact raw evidence: `raw.zip` (SHA-256 `6e840aec4293a86b41c641cccec5c73c20441ffca4f6b7b4b9b4937fd1f7f47e`), containing `provenance.txt`, `summary.txt`, `SHA256SUMS` and `raw/` outputs. All listed file checksums verified after extraction.

Classification: statements above are **OBSERVED ON RUNNER** unless marked unknown. GitHub's documented VM allocation appears in the parent README. Mapping a guest model to vendor microarchitecture is an inference, not an observed physical host property.
