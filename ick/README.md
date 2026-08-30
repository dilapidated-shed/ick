# ICK source

`gcc/` is the pinned, unmodified GCC reference. `ick/source/` contains the
complete source files that ICK changes or adds. The ICK files are ordinary
source files rather than a replayed patch series, so they can diverge from GCC
deliberately.

The first import is squashed: this repository records the exact old source
commit in `SOURCE.lock`, but it does not import GCC's enormous commit history
or the transitional `isomorphisms/rhs` history.

Materialize the currently buildable compiler without changing the reference:

```sh
git submodule update --init gcc
sh ick/materialize.sh gcc build/ick-source
```

The materializer refuses the wrong GCC commit, verifies every ICK source file,
and refuses to overwrite an existing output directory. Builds use the
materialized directory; development changes belong in `ick/source/`, not in
the reference submodule or generated output.
