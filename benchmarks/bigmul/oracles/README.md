# Oracle qualification

The checker builds an explicitly identified schoolbook control through MB01,
then compares its actual output directly to Python integers for every pair in
0..255 and the complete v2 smoke corpus. The control role does not establish
paper-candidate admission. bc is required by default; its absence returns nonzero.
`--allow-missing-bc` records PASS_PYTHON_ONLY and omitted cross-oracle coverage.

When bc is present, the exact executable/version/hash and sampled coverage are
recorded. Scale is zero, output base is set before input base, hexadecimal operands
are uppercase and continuation lines are unfolded. Blank/extra output, diagnostics,
nonzero status and timeouts fail. The installed bc implementation is never assumed
to be Berkeley bc. Version output is recorded even when that implementation does
not support `--version`.

An optional precomputed TSV cache binds every exact case hash and signed product,
plus content SHA-256. The emitted receipt gives Python origin/version and candidate
identity. Consumers must pin that receipt/content hash; a self-generated cache
checksum alone is not trusted provenance. Oracle work remains outside timing.
Actual bc execution, GMP and candidate-oracle independence remain pending where
the corresponding executable/provider has not been qualified.
