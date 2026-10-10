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

## Earth 4B: Linux x86_64 candidate bundle

The existing dmd-runtime.yml qualification remains the compiler/runtime producer.
It checks out source **exactly at** 45a65d8b8c8928843b1bdaa1e737ce8b5ae814e0.
The candidate packager is obtained independently from the workflow's head commit,
not built or installed in place of the pinned IDK source. Changes to this
packaging code therefore do not silently change the language implementation.

Once ordinary-D, divergent-IDK, mutant and conservative negative controls
pass, package-candidate.sh packs the owned compiler at
dmd/generated/linux/release/64/dmd as libexec/idk-dmd, two distinct static
libraries (libdruntime.a, libphobos2.a), generated druntime imports
(including object.d), and the upstream-pinned Phobos module trees.
bin/idk is a relocatable Bash wrapper with explicit -conf=, import and
archive paths. Declared host linker dependencies are pthread, m, dl and
a C linker/toolchain on Linux x86_64. This is not a completely static
operating-system toolchain; libc and host linking support are external.

The archive includes meta/identity.tsv, original source/runtime locks,
unaltered fixture sources, meta/FILES.sha256 for each regular member other
than the checksum list itself, and offline share/verify-candidate.py.
The producer publishes one idk-linux-x86_64-<source>.tar.gz CI candidate and
separate candidate-archive.sha256; the archive digest cannot be embedded
in the archive itself. Tar ordering, owners and timestamps are normalized
and gzip is -n. Binary contents are fingerprinted; **the build is not
claimed bit-identical** across differing compiler, linker or OS images.

A second fresh-host runner downloads the archive, verifies the digest and
extracts it **without checking out the repository**, using bin/idk instead
of an installed D compiler. It compiles and executes both unchanged fixtures,
tests the independently generated multiplication-to-minus mutant (required exit
exactly 3), and demonstrates rejection of missing libraries, swapped source/
runtime pins, wrong-ABI ELF objects in both archives, and altered import files.
It validates the restored tree after negative tests. This separate job uploads
its own fresh-consumer.tsv plus stdout/exit/error evidence.

The conservative-DMD binary, ldmd2 bootstrap and runtime build trees
are deliberately absent from the archive. Conservative-DMD rejection remains
producer-side evidence and can never act as a fresh-consumer fallback.

Historical comparison anchors to [successful run 37304142154](https://github.com/dilapidated-shed/ick/actions/runs/37304142154),
the exact SOURCE.lock and RUNTIME.lock, and unchanged fixture fingerprints
and expected outputs. Do not infer byte-for-byte equality of generated objects
across different build environments. CI artifacts are *candidates*, not
releases, Android acceptance, or permission to merge.
