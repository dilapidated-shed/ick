# D/Icky D runner memory research

## Scope and base

This branch starts at `dmd-betterc-float-init` commit
`2683df6ea5d71742e98f89b1fe41371ccb017c99`. It prepares identification
and source material for later memory/fetch work. No throughput measurements or
representation choice belong in this branch.

## Existing work inventory

| Existing material | Location | What it establishes |
| --- | --- | --- |
| MIRO A1 hardware and SC9863A source map | [cheap-phone-os hardware](https://github.com/fuego-ironworks/cheap-phone-os/tree/main/hardware) | Physical phone identity and source hierarchy. It does not characterize the hosted x86 guest. |
| Low precision C contract and qualification | [imprecise types](../../docs/imprecise-types.md), [header](../../ick/include/ick/imprecise.h), [qualification](../../qualification/imprecise-types/) | Byte storage and encode/decode semantics, including storage-only unsigned E5M3. |
| Icky DMD compact types | `dmd/source/ick/representations/` and `dmd/qualification/representations/` on the compact/geometric representation branches | Semantic tests and value types; inspect the branch actually used for subsequent D kernels. |
| DMD build and normal-D runtime gate | [DMD runtime workflow](../../.github/workflows/dmd-runtime.yml) | Compiler and runtime execution on a hosted Ubuntu runner, not a hardware fingerprint or throughput result. |
| Separate x86-64 backend | [Idriç x86 backend](https://github.com/fuego-ironworks/idric-x86-aggressive-backend) | Scalar target primitives and direct ELF execution, including compact numeric formats; no inference about D backend vectorization. |
| D references | [Programming in D](../../references/d/README.md) | Existing book mirror and provenance; do not duplicate it here. |

This repository's inspected DMD branch has no dedicated cache, memory-channel,
fetch-width, or SIMD-throughput benchmark corpus. The linked phone map records
platform identity, not measured memory hierarchy. A later job should inspect
other research branches before treating absence here as absence everywhere.

## Hosted target: GitHub documentation

Primary identification target: **standard `ubuntu-24.04` x64**. Pinning the
image label avoids a moving `ubuntu-latest` OS selection. GitHub's
[runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
(retrieved 2026-09-28) states that a **public repository** gets a fresh Linux
VM per job with **4 CPUs, 16 GB RAM, 14 GB SSD, x64**. For a **private
repository**, the same label gets **2 CPUs, 8 GB RAM, 14 GB SSD**. This
repository was public when inspected. Ubuntu 24.04 is an image selection, not
a guarantee about the exact kernel/image revision. GitHub promises no
processor model, socket topology, cache configuration, memory-channel count,
memory clock, SIMD width, bandwidth, or exclusive physical core. The runner
reference calls standard non-slim jobs virtual machines; it does not promise
the hypervisor vendor or expose physical DIMMs. Larger runners require a
separate provisioned offering and are outside this first target.

## Layout and evidence

- `../runner-hardware.yml`: three independent identification jobs in one
  workflow run; manual reruns permit observations across allocations.
- `fingerprints/<run-id>-<attempt>-<sample>/`: one committed raw artifact
  extracted from each job, plus a normalized account. Never replace raw data
  with summaries. `provenance.txt` identifies the job and its source SHA.
- `references.tsv`: source ledger with URL, revision/date, retrieval date,
  reason for retention and link-only disposition. Vendor manuals remain at
  upstream URLs; no enormous or unclearly licensed PDF is copied here.
- `research-map.md`: current evidence status and the bounded next job.

Workflow artifacts expire after 90 days. Commit the relevant original files
and their SHA256SUMS under `fingerprints/` before expiry. A benchmark must
cite the exact fingerprint directory and its own compiler revision, flags,
working set and run URL. Do not substitute a later allocation's fingerprint.
If a job fails to expose a field, retain that absence as unknown.

The probe reads guest-visible files and compiler target reporting only.
`/proc/cpuinfo`, sysfs and `lscpu` describe what the guest sees. A cache
descriptor is not proof of physical ownership or effective cache capacity.
A `-march=native` report describes compiler-visible features, not measured
vector instruction throughput. `/proc/self/numa_maps` reflects this process,
not host NUMA wiring. No kernel or DIMM claims are inferred from a marketing
processor name.
