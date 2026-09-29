# Compiler inspiration

This branch keeps exact upstream compiler source snapshots available for study.

These repositories are references, not claims about ICK ancestry. ICK remains
GCC-derived. Do not copy source from one of these trees into `ick/source/`
without recording provenance and preserving the upstream license.

The submodules are shallow by default because the purpose is to inspect source,
not import each project's full history.

## References

- `clang/` — LLVM/Clang, industrial C frontend and LLVM-based toolchain.
  Pinned from `llvm/llvm-project` `main` at
  `d7daf1d24be8231f7f422ef2bca1003d4b77ec11`.
- `tinycc/` — TinyCC, compact compiler, linker, assembler, and JIT.
  Pinned from `TinyCC/tinycc` `mob` at
  `9db1105c32afd3dcf0c28b8186f08e63c761b2b5`.
- `chibicc/` — small readable C compiler intended for learning compiler
  implementation. Pinned from `rui314/chibicc` `main` at
  `90d1f7f199cc55b13c7fdb5839d1409806633fdb`.
- `cproc/` — small C11 compiler targeting QBE.
  Pinned from `michaelforney/cproc` `master` at
  `d1c53ddf56571573a7025324c8dd5c6d547a4d1f`.
- `lacc/` — compact C compiler with its own frontend and code-generation
  structure. Pinned from `larmel/lacc` `master` at
  `30839843daaff9d87574b5854854c9ee4610cdcd`.
- `8cc/` — Rui Ueyama's earlier small C compiler, useful beside chibicc.
  Pinned from `rui314/8cc` `master` at
  `b480958396f159d3794f0d4883172b21438a8597`.
- `cparser/` — C frontend built around libFirm.
  Pinned from `libfirm/cparser` `master` at
  `81330da3ee9650c88a1afdc93de654b9dfd9fb78`.
- `compcert/` — formally verified optimizing C compiler.
  Pinned from `AbsInt/CompCert` `master` at
  `66a9fd06ef88619cc94765ca995a1018f7259b5c`.
- `pcc/` — Portable C Compiler lineage, useful for older retargetable compiler
  organization. Pinned from `PortableCC/pcc` `master` at
  `201554009decadafd2af7c7d1dd631e583967dd8`.
- `slimcc/` — compact optimizing C compiler.
  Pinned from `fuhsnn/slimcc` `main` at
  `9778925e26ec13ea97fb0cba611d6d0ed608be6a`.
- `c4/` — deliberately tiny C compiler/interpreter, useful as a lower bound on
  compiler structure. Pinned from `rswier/c4` `master` at
  `2feb8c0a142b2e513be69442c24af82dbaf41a25`.

GCC is not duplicated here because the repository already pins GCC at
`gcc/` as ICK's actual compiler foundation.

To populate the source after checking out this branch:

```sh
git submodule update --init --recursive
```

Each reference remains governed by its own upstream copyright and license
notices.

## Discussion notes

- [`gcc-contrast-notes.md`](gcc-contrast-notes.md) — first research pass through public discussions and project documentation contrasting each reference compiler with GCC, with questions for ICK rather than design conclusions.

- [`kernel-construct-corpus.md`](kernel-construct-corpus.md) — Linux-kernel-derived real-world C construct suite tied back to constructs already used in ICK/Wegert/Pauli; this is now the preferred source-archeology corpus.
