# ICK source

`gcc/` is the pinned, unmodified GCC reference. `ick/source/` contains the
complete source files that ICK changes or adds. `ick/PRUNE` contains the exact
reference-tree paths that ICK intentionally removes. The ICK files and prune
manifest are ordinary owned source state rather than a replayed patch series,
so they can diverge from GCC deliberately.

The first source import is squashed: this repository records the exact old
source commit in `SOURCE.lock`, but it does not import GCC's enormous commit
history or the transitional `isomorphisms/rhs` history. The C-only pruning is
likewise pinned there to the green RHS receipt
`6a1f781fb036a110c5f4dacff9a12769a5b0a706`.

Materialize the currently buildable compiler without changing the reference:

```sh
git submodule update --init gcc
sh ick/materialize.sh gcc build/ick-source
```

The materializer refuses the wrong GCC commit, verifies every ICK source file
and every prune path, refuses to overwrite an existing output directory,
archives the pinned reference, removes the owned prune set, and then applies
the ICK source files. Builds use the materialized directory; source changes
belong in `ick/source/`, intentional reference-tree deletions belong in
`ick/PRUNE`, and neither belongs in the reference submodule or generated
output.
