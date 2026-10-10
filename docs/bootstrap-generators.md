# ICK C-only bootstrap generator boundary

Scope: owned ICK source at `c61e448251744a2f40ad743ebef1a027bdcd2f9d` and its pinned GCC reference `6294f1d9e7536e5ffcde09d1528c918d63abfef5`. This is a dependency classification, not a claim that ICKY is already wired into GCC.

## Three different boundaries

| Component | Input and role | Status |
| --- | --- | --- |
| GCC COBOL parser generation | `gcc/cobol/Make-lang.in` invokes Bison to produce `parse.cc` and `cdf.cc` | **Pruned.** `ick/PRUNE` removes `gcc/cobol`, `libgcobol`, and its tests; these rules do not establish a Bison dependency for the materialized C-only source |
| GCC `gengtype` support generator | `gcc/gengtype-lex.l` is transformed by Flex into build-local `gengtype-lex.cc`; `gcc/gengtype-parse.cc` is a separate handwritten parser for a subset of C declarations/GTY annotations | **Retained GCC bootstrap component**, not the ICK source-language parser. The pinned reference does not contain a checked-in `gengtype-lex.cc` |
| ICKY source parser | `dilapidated-shed/icky` declares `parse : String -> Either (List Diagnostic) Program`, retaining source glyphs and spans | **Not integrated into ICK's GCC C frontend.** The small current grammar does not parse the required GCC C or `gengtype` inputs. Do not claim otherwise |

ICK's C frontend still contains the GCC-derived `gcc/c/c-parser.cc` implementation. A parser for ICK expressions is a different responsibility from a build-time lexer for GCC's `gengtype` metadata generator. Replacing one must not silently replace, or break, the other.

## Historical evidence and open qualification

The [October 8, 2026 C-only qualification](https://github.com/dilapidated-shed/ick/actions/runs/37804725191) installed Bison and Flex and its configure log reports `checking for bison... bison -y`. This is evidence of detection, **not** a demonstrated Bison generation call. The same build log shows `flex -ogengtype-lex.cc ../../source/gcc/gengtype-lex.l`, compilation of `build/gengtype-lex.o`, and a successful `gengtype` link. Flex use at that bootstrap boundary **was** observed.

A historical log cannot establish how the build behaves with Bison unavailable, and a grep through GCC source cannot establish which generators a particular build actually executes.

The C-only qualification now runs with a Bison/Yacc shadow and process-level `execve` traces across configure, build and install. It distinguishes version/help probes from generation attempts, and checks for unshadowed absolute-path Bison/Yacc execution. The four Android ABI build lanes use the same deny/shadow control but do not yet retain their own system-call traces. A passing guard is evidence only for the concrete build revision and host configuration that ran it.

Flex remains an **explicit foreign GCC bootstrap dependency** while `gengtype-lex.cc` is generated from `gengtype-lex.l`. Its executable version and the generated source hash must be recorded; there is no authorization to call it ICKY or to treat a provisioned package as a compiler-runtime dependency. No separate Flex removal or lexer rewrite has been qualified.

## Architecture and next steps

The intended ICKY language-parser work lives under [Flexible Pipes #71](https://github.com/isomorphisms/flexible-pipes/issues/71), with [ICKY PR #4](https://github.com/dilapidated-shed/icky/pull/4) retaining the unfinished typed AST work. Reconcile that branch before implementing a versioned, executable ICKY consumption boundary. Its future qualification must observe the parser actually running, preserve source glyph/position fidelity, and independently check accepted and rejected syntax against produced ICK compiler behavior.

If replacing Flex in `gengtype` is desired, that is a **separate GCC-generator compatibility project**. It requires an equivalent lexer/token contract against the handwritten `gengtype-parse.cc`, generated `gtype` records, and negative cases before the Flex bootstrap use can be eliminated. ICKY's existing five-glyph noun-last grammar does not supply that equivalence.

Cat Food [matrix #89](https://github.com/isomorphisms/catfood/issues/89) owns the build-host inventory. Flexible Pipes is the mandatory job boundary, and ai-ci independently accepts exact tool/target evidence. This source audit or an unaccepted pull request must not be promoted to a published compiler or runtime qualification.
