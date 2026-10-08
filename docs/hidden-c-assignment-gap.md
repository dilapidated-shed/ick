# Hidden C assignment gap and downstream review — 2026-10-07

During the FastChat FC-D1/FC-S1 preflight, the owned ICK C frontend rejected
literal U+2190 `←` assignment while the ordinary-`=` compiler control passed.
Known defective main snapshot:
`e3c2a40b4edafc4d9caca55d1f7c094e6aab9589`.
The available compiler at `7afb1820cd59c0c51d19a7e37902c14f4466f442`
had an identical owned compiler layer.

The user reports that this expectation stayed unverified for a long time and
warns that existing C files across hundreds of repositories may have used
ordinary assignment instead of the intended Icky notation. Earliest bad
revision, duration, affected-file count and downstream consequences are
**UNKNOWN**. Every maintained C file is a review candidate; no fleet audit
has run and no blanket program-failure claim is made.

Source repair `2a27ad6ab4e4601c9a0e4a5fa7915712db707af0` maps the existing
UTF-8 token in the C frontend after preprocessing. The exact probe now passes,
with semantic and negative regression evidence in
[the qualification receipt](../qualification/c-assignment-arrow/receipt.tsv).
This fixes the demonstrated C syntax gap. It does not establish coverage of
other glyphs, update installed compilers, correct inherited source style, or
rebuild existing consumer artifacts.

The wider obligation stays in
[ai-ci issue #217, “Regression: preserve functorial ICKY C instead of falling back to generic C/game idioms”](https://github.com/isomorphisms/ai-ci/issues/217):
inventory C source, headers/generators, current repositories and active
branches; review assignment and initializer spellings against intended
profiles; investigate compiler substitutions, hidden rewrites and historical
completion claims; and requalify confirmed consumers using exact source,
compiler/frontend and artifact identities.

First-party Icky source, approved ordinary-C boundaries, compiler bootstrap,
generated C and foreign/vendored source need distinct source roles. Normal
C `=` can compute correctly while violating the requested notation.
Syntax-aware review must preserve comparisons, strings/comments, `*`
pointer/dereference and `->` member access. Do not perform a global replacement.

Cross-links:
[Flexible Pipes executable checks](https://github.com/isomorphisms/flexible-pipes/issues/9),
[Flexible Pipes symbol fidelity](https://github.com/isomorphisms/flexible-pipes/issues/22),
[Cat Food compiler/artifact matrix](https://github.com/isomorphisms/catfood/issues/89).

The assignment audit remains open after the compiler repair. Physical MIRO A1
execution remains **BLOCKED/NOT_RUN** for the recorded compiler fixture.
