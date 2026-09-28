# Sample 2: normalized guest fingerprint

- Provenance: [workflow run 36399380725](https://github.com/dilapidated-shed/ick/actions/runs/36399380725), attempt 1, matrix sample 2; [original artifact 10959925298](https://github.com/dilapidated-shed/ick/actions/runs/36399380725/artifacts/10959925298).
- Checkout source: pull-request synthetic merge `6ae8adf6a18a5d2677411ebbe458547eb496212c`; actual PR head `9704eebfd35883783b316a3955981c2aa489e4a5`. Identification code is independent of checkout.
- Label and date: `ubuntu-24.04`; 2026-09-28T08:46:36Z.
- Guest OS/kernel: Ubuntu 24.04 label; `6.17.0-1022-azure`; x86_64.
- Guest CPU: INTEL(R) XEON(R) PLATINUM 8573C; 6/model 207/stepping 2; 4 logical CPUs, reported 2 cores × 2 threads × 1 socket, one reported NUMA node.
- Guest cache: L1d 48 KiB per reported instance ×2; L1i 32 KiB ×2; L2 2 MiB ×2; L3 260 MiB ×1; 64-byte coherency line reported for all levels. These descriptors do not prove the guest owns the whole cache.
- Compiler-visible features: AVX2 and AVX-512 flags present; inspect raw flags and OS state before executing any subset; GCC native target sapphirerapids.
- Guest virtualization: Microsoft hypervisor, full virtualization as reported by `lscpu`.
- Guest memory/page: `MemTotal 16372440 kB`; 4096-byte base page, zero preallocated huge pages in raw `meminfo`.
- Unknown: physical CPU allocation, host siblings, DIMMs/channels/speed, host NUMA location, effective cache share, bandwidth, load concurrency, sustained vector width/throughput and access to performance counters.
- Exact raw evidence: `raw.zip` (SHA-256 `d8c8b4ec81bd84a36e094819d12c95f5c6727e9efa8ed79f67dd62d79ce8218e`), containing `provenance.txt`, `summary.txt`, `SHA256SUMS` and `raw/` outputs. All listed file checksums verified after extraction.

Classification: statements above are **OBSERVED ON RUNNER** unless marked unknown. GitHub's documented VM allocation appears in the parent README. Mapping a guest model to vendor microarchitecture is an inference, not an observed physical host property.
