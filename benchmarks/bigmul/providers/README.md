# MB05 conventional comparison providers

These are bounded benchmark controls for the existing MUL6 handoff. They do
not implement the paper path or select a compiler algorithm.

| Provider | Arithmetic and representation | Costs at the 32-bit interface |
| --- | --- | --- |
| schoolbook | Existing `mul_schoolbook`, unchanged | Existing quadratic limb loop |
| karatsuba32-bounded | Difference-form Karatsuba; schoolbook at widths ≤16 | Power-of-two padding and recursive allocation included |
| gmp-mpn-mul | GMP 6.3.0 `mpn_mul`, native 32/64-bit limbs without nails | Packing, trimming, allocation, multiplication, export and free |
| gmp-mpn-sqr | Explicit GMP 6.3.0 `mpn_sqr` | Same conversion costs; admits equal values and equal stored lengths only |

The recursive and GMP adapters admit 1–2048 stored 32-bit words per operand.
Null pointers, zero lengths and excess widths return nonzero. Arrays must be
aligned; the caller supplies `na+nb` output words, disjoint from either input.
Every output word is written, including leading zeroes. Input arrays may
alias each other; equal-value tests use distinct buffers. The bare C interface
cannot observe an undersized caller allocation. The correctness driver checks
guards, different prefills and preserved input snapshots.

No retained recursive provider was found in the inspected MUL1, MUL5 or original
benchmark branches. The small control here uses the difference form so recursive
operands keep exactly half the padded width. Both signs of the cross term,
carry chains and recursion boundaries are checked. It is deliberately bounded,
allocates scratch recursively and is not a tuned production bigint library.

GMP preparation packs 32-bit words by value, rather than casting their storage.
Odd counts on a 64-bit build get a zero high half. High native zero limbs are
trimmed while zero retains one limb. General multiplication orders the longer
native array first. Equal values do not silently select squaring: the explicit
square entry point checks equality first. See GMP's official
[low-level contracts](https://gmplib.org/manual/Low_002dlevel-Functions).
Unsupported nail/limb configurations fail to compile. The driver verifies the
runtime/header pair and pins version 6.3.0, recording actual header/library
hashes, observed configuration fingerprint, package query and dynamic linkage.
Original build flags and internal selected GMP algorithms remain UNKNOWN.
GMP is [LGPLv3+ or GPLv2+](https://gmplib.org/manual/Copying); no GMP code or
library binaries are copied into this repository.

Run `python3 benchmarks/bigmul/providers/check_mb05.py`. By default missing GMP
is an error. `--allow-missing-gmp` explicitly records omitted coverage. Separate
`--gmp-include DIR` and `--gmp-library FILE` arguments permit an extracted matching
development package and existing shared runtime, without a system installation.
Compiler selection uses `CC` as one executable, never a shell recipe.

All general providers receive the identical medium-v2 stored operand bytes
and every immutable legacy-v1 pair; the smoke/legacy files remain hashed.
Signed semantic cases
and the original acceptance corpus also pass through MB01's explicit binary
selector and the shared guarded `--pipe` wrapper. Each general provider checks
every 0..255 pair directly through legacy-v1; the square provider maps the same
corpus to squares of its left operands, including every byte square.
Additional fixtures include odd widths, swapped imbalance, padded zeroes,
both Karatsuba difference signs and the 2048-word bound. Full normal and
optimized Python runs must reject the compiled GMP high-half repacking mutant
through a nonzero outer worker status. Child crashes/timeouts cannot pass.

`gmp_fixture.c` exposes two separate diagnostic measurements via MB06:

| Mode | Measured operation | Outside the interval |
| --- | --- | --- |
| native | Prepared `mpn_mul` or `mpn_sqr` call | Input generation, packing, allocation, trimming, export and exact checking |
| adapter32 | Complete 32-bit adapter call | Input generation, independent expected products and checking |

Each records three raw eight-call batches per request with CLOCK_MONOTONIC.
These short, uncalibrated diagnostics qualify boundaries, not speed rankings.
The native mode reuses its prepared storage; adapter32 allocates each call.
Every batch's full output is checked independently after measurement. Square
requests derive a separate suite from each source row's left operand; the
effective input hashes and explicit mapping distinguish this from the original
general-product corpus. No equality is claimed between those two workloads.

The JSON receipt contains complete build/worker commands, stdout/stderr/status,
source/compiler/binary/corpus hashes, provider outcomes and raw samples.
Use `--output FILE` to retain it. Integrated MB21 receipts embed it, and the
native x86-64/ARM64 workflow archives the complete campaign receipt. Host GCC
controls, qualified ICK, ordinary 32-bit builds, physical A1 and AIX remain
separate evidence boundaries. MB07–MB13 and MB16 can consume these controls;
full campaign readiness still refuses while their required work is missing.
