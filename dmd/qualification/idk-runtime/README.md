# IDK full-runtime qualification

This lane starts from IDK `297112cc526cddbba098716d1617681852b8c4c9`,
including runtime slice `d782f734ca4e8cfd4f8a77e4a02780133904e6b9`.
It builds the owned IDK compiler, then the exact druntime and Phobos sources
named in `dmd/RUNTIME.lock`, and executes both versioned fixtures on Linux
x86-64 without `-betterC`.

The shared receipt fields come from F02a at
`4e1663183a1abc7d6182b305160a3ea6f98247fe`. Only field names are reused.
`reconciled_f01_head` is `NOT_APPLICABLE` in this independent IDK lane.
The ordinary-D fixture preserves this lane's historical program; it is not
the conservative branch's fixture.

Two TSV receipts retain independent fixture hashes and execution statuses:

- `ordinary-d-receipt.tsv` records ordinary-D runtime qualification.
- `divergent-syntax-receipt.tsv` additionally records the IDK source head,
  lexer/parser paths and hashes, all seven Unicode codepoints, mutation
  results, and conservative-compiler controls.

The Unicode mutant replaces the multiplication token in `3 × 4 ≟ 12`
with mathematical minus. It must compile with IDK and exit exactly 3 after
running allocation, BigInt, exceptions and output. A crash or unrelated
compiler failure does not satisfy that control.

A separate compiler is built from the exact conservative F02a source head
in its own checkout. Only its rejection is used as a syntax control.
It must execute the ordinary-D fixture successfully and reject the original
IDK fixture with the invalid U+2192 token diagnostic. Its ordinary-D success
cannot supply a divergent-syntax PASS.

Provenance validation precedes external checkouts, rejects absent, duplicate
or mismatched lock entries, and requires the owned compiler tree to match the
specified IDK base. Receipt statuses come from individual step outcomes;
skipped stages remain `NOT_RUN`. Input manifests, stdout, control diagnostics,
exit codes, compiler/library digests and both receipts are retained as an
artifact named for the exact tested source head.
