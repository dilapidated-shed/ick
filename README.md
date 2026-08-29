# ICK

Isomorphismes' C Kompiler.

ICK is the general/C compiler line. IRK is the separate R experiment.

## Compiler foundation

ICK is GCC-derived. The live GCC-derived compiler source is still in the transitional `isomorphisms/rhs` repository; this repository is not yet allowed to pretend that its small wrapper is the complete compiler. Moving the compiler source of truth here, while preserving GCC history and licensing, is foundation work rather than packaging trivia.

See:

- [`LICENSING.md`](LICENSING.md) for the GCC/runtime/model licensing boundaries.
- [`docs/targets.md`](docs/targets.md) for the orthogonal target model.
- [`docs/android-release-gate.md`](docs/android-release-gate.md) for the Android/F-Droid compiler qualification matrix.

The existing AArch64 work is evidence that ICK can participate in an Android build, but it is not yet evidence that ICK can build every release ABI. Release qualification is explicit and per target.

## Meaning model

The first shared component in this repository is a small meaning model for turning words in a binding name into proposed compiler claims. For example, `image` or a close word such as `picture` can propose the semantic kind `Image`. A target compiler must then check that claim with actual type evidence; vector similarity is not the check.

The model is deliberately the same pinned artifact used by IRK so that a word does not change meaning merely because the output language changed.

```sh
sh model/fetch.sh
```

The working R prototype lives at https://github.com/isomorphisms/irk.
