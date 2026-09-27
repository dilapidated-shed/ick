# Mars DMD line

This directory is the standalone Digital Mars DMD cousin of the GDC line.

The baseline source is pinned to DMD v2.113.0, commit
`74917954b53f7f35b13e61b4438c7253834929ed`.  The owned snapshot contains
`compiler/src/dmd` plus the small set of upstream build metadata needed to
build that compiler.  It deliberately does not import druntime, Phobos, the
language specification, upstream CI configuration, repository history, or the
upstream compiler test suites.

`SOURCE.lock` records the exact provenance after the one-shot loader has run.

Baseline build on a machine with a D compiler and C++ compiler:

```sh
cd dmd/compiler/src
./build.d dmd HOST_DMD="$(command -v dmd)"
```

The repository qualification uses `ldmd2` as the host-DMD-compatible driver.
The baseline gate also compiles one `-betterC` object so code generation is
exercised without importing the D runtime.

This loading step does not add Icky D Unicode syntax.  That remains the next
front-end change on the `dmd` branch (issue #12).
