# ICK

Isomorphismes' C Kompiler.

ICK is the general/C compiler line. IRK is the separate R experiment.

## Compiler foundation

ICK is GCC-derived. This repository now owns the ICK source layer: `gcc/` is
an immutable ordinary-GCC reference, while [`ick/source/`](ick/source/) holds
the complete compiler files changed by ICK. [`ick/materialize.sh`](ick/materialize.sh)
combines those checked inputs into a build tree without changing the reference.

The import is deliberately squashed. [`ick/SOURCE.lock`](ick/SOURCE.lock)
records both the GCC base and the formerly live `isomorphisms/rhs` ICK source
commit without pulling either repository's enormous history into this one.

See:

- [`LICENSING.md`](LICENSING.md) for the GCC/runtime/model licensing boundaries.
- [`docs/targets.md`](docs/targets.md) for the orthogonal target model.
- [`docs/android-release-gate.md`](docs/android-release-gate.md) for the Android/F-Droid compiler qualification matrix.

The existing AArch64 work is evidence that ICK can participate in an Android build, but it is not yet evidence that ICK can build every release ABI. Release qualification is explicit and per target.

To materialize the compiler source:

```sh
git submodule update --init gcc
sh ick/materialize.sh gcc build/ick-source
```

See [`ick/README.md`](ick/README.md) for the source-ownership rule.

## Meaning model

The first shared component in this repository is a small meaning model for turning words in a binding name into proposed compiler claims. For example, `image` or a close word such as `picture` can propose the semantic kind `Image`. A target compiler must then check that claim with actual type evidence; vector similarity is not the check.

The model is deliberately the same pinned artifact used by IRK so that a word does not change meaning merely because the output language changed.

```sh
sh model/fetch.sh
```

The working R prototype lives at https://github.com/isomorphisms/irk.
