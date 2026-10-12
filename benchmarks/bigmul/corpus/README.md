# Shared operand corpus

`mul-v1.tsv` is copied verbatim from ComputerScience commit
`32aa3dc5e0e9c2dd19eacb05e515894e252d0886`; its SHA-256 is
`96e5ce0181dc92b269e444bc63c8f63684c56ad476474094b193ce4cd474f5f3`.
Its bit-width columns are historical domain limits, not mathematical bit lengths.

The new `limb32-corpus-v2` TSV stores actual operand bytes as lowercase hex of
little-endian uint32 limbs. Zero has at least one stored limb and sign zero.
Stored lengths preserve leading zero limbs; mathematical bit lengths describe
the values. Signed wrapper cases and unsigned kernel cases have different labels.
Equal values in distinct buffers are distinct from a specialized square call.
Each row hash covers every preceding tab-separated field, without a newline.
The trailer contains the row count and SHA-256 of all preceding bytes, including
their newlines. A missing/truncated trailer fails validation.

Random instances use SplitMix64 modulo 2^64, seeded by the first eight bytes of
SHA-256(case ID), interpreted little-endian. Every case generates its own stream;
enumeration order and larger suite budgets preserve all previous case bytes.
The fixed SplitMix64 constants and known vector appear in the executable source.
No native-endian serialization or Python random sequence enters this format.

Smoke caps operand family widths at 129 bits; medium at 4097 and large at 16385.
Each size uses bounded families and instances, rather than a Cartesian product.
Transform/padding thresholds are pending the accepted implementation's domain.
`check_mb03.py` checks both source corpus identity and v2 corruption controls.
